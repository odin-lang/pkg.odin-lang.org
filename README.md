# pkg.odin-lang.org

This is the documentation generation tool for [pkg.odin-lang.org](https://pkg.odin-lang.org).

It works be reading a `.odin-doc` file and generating the needed documentation for the packages in HTML.

GitHub Actions automatically generates the site each night from the master Odin branch by generating the `.odin-doc` file from the `examples/all` package.

* Doc Format: https://github.com/odin-lang/Odin/blob/master/core/odin/doc-format/doc_format.odin
* examples/all: https://github.com/odin-lang/Odin/tree/master/examples/all