import 'package:flutter_test/flutter_test.dart';
import 'package:kelola/domain/k8s/cluster_kind.dart';

/// M48.1 §1: every row of the distro table.
void main() {
  group('openShiftDistroFrom', () {
    test('version containing okd (any case) is OKD', () {
      expect(openShiftDistroFrom(version: '4.17.0-okd-scos.0'), OpenShiftDistro.okd);
      expect(
        openShiftDistroFrom(version: '4.15.0-0.okd-2024-03-10-010116'),
        OpenShiftDistro.okd,
      );
      expect(openShiftDistroFrom(version: '4.17.0-OKD-scos.0'), OpenShiftDistro.okd);
    });

    test('non-empty version without okd is OCP', () {
      expect(openShiftDistroFrom(version: '4.17.3'), OpenShiftDistro.ocp);
    });

    test('version wins over osImages', () {
      expect(
        openShiftDistroFrom(
          version: '4.17.3',
          osImages: ['CentOS Stream CoreOS 417.9.202410150733-0'],
        ),
        OpenShiftDistro.ocp,
      );
      expect(
        openShiftDistroFrom(
          version: '4.17.0-okd-scos.0',
          osImages: ['Red Hat Enterprise Linux CoreOS 417.94'],
        ),
        OpenShiftDistro.okd,
      );
    });

    test('empty version + CentOS Stream CoreOS or Fedora CoreOS image is OKD',
        () {
      expect(
        openShiftDistroFrom(
          osImages: ['CentOS Stream CoreOS 417.9.202410150733-0'],
        ),
        OpenShiftDistro.okd,
      );
      expect(
        openShiftDistroFrom(osImages: ['Fedora CoreOS 39.20240210.3.0']),
        OpenShiftDistro.okd,
      );
    });

    test('empty version + RHCOS image is OCP', () {
      expect(
        openShiftDistroFrom(
          osImages: [
            'Red Hat Enterprise Linux CoreOS 417.94.202410090854-0 (Plow)',
          ],
        ),
        OpenShiftDistro.ocp,
      );
    });

    test('empty version + mixed OKD and RHCOS images is unknown', () {
      expect(
        openShiftDistroFrom(
          osImages: [
            'Fedora CoreOS 39.20240210.3.0',
            'Red Hat Enterprise Linux CoreOS 417.94',
          ],
        ),
        isNull,
      );
    });

    test('nothing usable is unknown', () {
      expect(openShiftDistroFrom(), isNull);
      expect(openShiftDistroFrom(version: '   '), isNull);
      expect(openShiftDistroFrom(osImages: ['', 'Ubuntu 22.04.4 LTS']), isNull);
    });
  });
}
