# OKD fixtures (M48.1)

All four files here are **synthetic**: hand-written to the shape of the real
objects, with the exact values named in `docs/specs/m48-1-okd.md` §5. Each
carries a top-level `"_synthetic"` key; parsers ignore it. Replace them with
captures from CRC's OKD preset (`crc config set preset okd`) when you have them.
