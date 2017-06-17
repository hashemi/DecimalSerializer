# DecimalSerializer

This package contains patched versions of `JSONSerialization` and `JSONDecoder` from the open source Swift project. The classes are modified to use `Decimal`s to replace all other number types (such as `Int`, `Float`). They are renamed `DecimalJSONSerialization` and `DecimalJSONDecoder`.

The patched versions only support decoding and deserialization and does not support encoding and serialization.

## Rationale
Floating point numbers are not a good choice for storing currency and financial information, where numbers are expected to be precise to a specific decimal point. This project was made to facilitate importing currency information serialized in JSON as numbers with decimal points by another legacy software that I have no control over.

## License
The original code by Apple is licensed under the Apache License 2.0 with Runtime Library Exception. This modified version is released under the same license.

## Author
Ahmad Alhashemi