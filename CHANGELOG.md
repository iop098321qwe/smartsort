# Changelog

All notable changes to this project will be documented in this file. See [commit-and-tag-version](https://github.com/absolute-version/commit-and-tag-version) for commit guidelines.

## [0.1.1](https://github.com/iop098321qwe/smartsort/compare/v0.1.0...v0.1.1) (2026-02-28)


### Features

* **undo:** increase default history depth to 10 ([2cdc972](https://github.com/iop098321qwe/smartsort/commit/2cdc9720a8e9e65d6f3e9b6fa12453bdbafdcc68))
* **undo:** store snapshots in XDG state with 3-level history ([80a6be6](https://github.com/iop098321qwe/smartsort/commit/80a6be6e21b98ab677e04f5533f0409bf2d4e4bc))

## [0.1.0](https://github.com/iop098321qwe/smartsort/compare/v0.0.2...v0.1.0) (2026-02-28)


### ⚠ BREAKING CHANGES

* **cli:** The -m mode flag is removed; sorting modes must now be passed positionally as ext, alpha, time, or size.
* **cli:** The -i option is no longer supported; refinement prompts now run automatically for ext, time, and size modes.

* **cli:** remove -i and always prompt refinements ([9dc77f2](https://github.com/iop098321qwe/smartsort/commit/9dc77f224fdf25700d0211b23a53e5afff2b5556))
* **cli:** replace -m with positional mode arguments ([dbdc06b](https://github.com/iop098321qwe/smartsort/commit/dbdc06b75863e89714d52a93f8b446555070dbbd))


### Features

* **cli:** prompt for mode on bare smartsort runs ([0805942](https://github.com/iop098321qwe/smartsort/commit/0805942e8d5c739174743ec1bc24af62b1a05e11))
* **kind:** add 'kind' mode with documents bucket ([d387766](https://github.com/iop098321qwe/smartsort/commit/d387766a1d105558c9aa00e6c14aaf5536a52dd7))
* **kind:** make kind the default suggested mode ([9d8f683](https://github.com/iop098321qwe/smartsort/commit/9d8f68344008c6e28fdd4d7a4d490df58e9a9070))
* **kind:** map archive extensions to archives bucket ([4dd057a](https://github.com/iop098321qwe/smartsort/commit/4dd057a72ad83acd818638420f6519d185d69683))
* **kind:** map audio extensions to audio bucket ([d2c8683](https://github.com/iop098321qwe/smartsort/commit/d2c868382b8beab4d875133b46eadcbbc9d7e3ed))
* **kind:** map binary extensions to executables bucket ([b36c4b0](https://github.com/iop098321qwe/smartsort/commit/b36c4b05c3407f628260944cba8d755096cb5b42))
* **kind:** map data extensions to data bucket ([0a5a264](https://github.com/iop098321qwe/smartsort/commit/0a5a26454ea4939dae40e5fac5848446dde44f7a))
* **kind:** map disk image extensions to disk-images ([b630195](https://github.com/iop098321qwe/smartsort/commit/b6301958161f85c0fa66c51229f17a513036429b))
* **kind:** map ebook extensions to ebooks bucket ([780b082](https://github.com/iop098321qwe/smartsort/commit/780b082c7f8ec63f051e54c2623a4e61a5950811))
* **kind:** map image extensions to images bucket ([eee91d3](https://github.com/iop098321qwe/smartsort/commit/eee91d327a23e54ddd487afdeab4ee5b8c0e3280))
* **kind:** map source extensions to code bucket ([5a8f945](https://github.com/iop098321qwe/smartsort/commit/5a8f9458ba4e3fedf37a3498ed5c3e0f3c6c8527))
* **kind:** map video extensions to video bucket ([0c192b4](https://github.com/iop098321qwe/smartsort/commit/0c192b41edb4d437cd81788adb7bc1a698b1564c))


### Bug Fixes

* **mode:** remove unsupported type sorting option ([f39ae77](https://github.com/iop098321qwe/smartsort/commit/f39ae77e45251af3ea900ea87f3d11f6e1a2a850))

## [0.0.2](https://github.com/iop098321qwe/smartsort/compare/v0.0.1...v0.0.2) (2026-02-28)


### Features

* **undo:** add smartsort undo subcommand ([82ffbc1](https://github.com/iop098321qwe/smartsort/commit/82ffbc15e77f42e44dec6239b21827e96eb98be3))


### Bug Fixes

* **undo:** remove directories created by sort run ([24ed957](https://github.com/iop098321qwe/smartsort/commit/24ed9574cb80cc58f78af217ed119dfb540597f8))

## 0.0.1 (2026-02-27)
