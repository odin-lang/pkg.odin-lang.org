# pkg.odin-lang.org

This is the documentation generation tool for [pkg.odin-lang.org](https://pkg.odin-lang.org).

It works be reading a `.odin-doc` file and generating the needed documentation for the packages in HTML.

GitHub Actions automatically generates the site each night from the master Odin branch by generating the `.odin-doc` file from the `examples/all` package.

* Doc Format: https://github.com/odin-lang/Odin/blob/master/core/odin/doc-format/doc_format.odin
* examples/all: https://github.com/odin-lang/Odin/tree/master/examples/all

## Markup rules

The generator uses simple markup rules to generate more structured documentation such as code blocks or examples.

### Blocks

1. A line starting with `Example:` will make subsequent lines that are indented with a tab a code block
2. A line starting with `Output:` or `Possible Output:` will make subsequent lines that are indented with a tab a block to note the output of the example
3. Indenting lines with a tab will wrap the indented lines with a preformatted tag (&lt;pre&gt;&lt;/pre&gt;)
4. The strings `Inputs:` and `Returns:` are automatically made bold as a convention for input and output of a procedure

There can be only 1 example, and only 1 output (or possible output) block in a doc block.

To make these work, you should not use a doc block with lines that start with spaces or stars or anything.
The convention is doc blocks like the following:

```odin
/*
Whether the given string is "example"

**Does not allocate**

Inputs:
- bar: The string to check

Returns:
- ok: A boolean indicating whether bar is "example"

Example:
	foo("example")
	foo("bar")

Output:
	true
	false
*/
foo :: proc(bar: string) -> (ok: bool) {}
```

### Inline

1. Inline code blocks are started and ended with a single \`, example: `code`
2. Links are created by 2 brackets, followed by the text, followed by a semi-colon, followed by 2 closing brackets, example: [[Example;https://example.com]]
3. Bold text is started and ended with 2 stars, example: **Foo**
4. Italic text is started and ended with 1 star, example: *Foo*
5. Starting line with a `-` makes the line a list item

## Using this to generate documentation for your packages

It is possible to generate a website similar to pkg.odin-lang.org for your packages.

To do this there is a config file you can reference as the second argument to this program.

Steps:

1. Build this project: `odin build . -out:odin-doc`
2. Just like `examples/all` linked above, create a file like this for the packages you want documented
3. Create the `.odin-doc` file: `odin doc path-to-step-1.odin -file -all-packages -doc-format`
4. Create a configuration file, explained below
5. Go into the directory where the docs should be generated, `website/static` for example
6. Generate the documentation by invoking the binary of step 1: `odin-doc path-to-.odin-doc path-to-config.json`

The directory you did step 6 in should now contain a html structure for any package that you referenced, and the packages it references.
You can now upload this to a static site host like GitHub pages.

### Example config

Here is an example config file with comments, you should remove any comments so that it is valid json.

```jsonc
{
	// Hides the core packages from the menu, homepage and search results,
	// they are still there so that links from your own packages work.
	"hide_core": true,
	// If your docs are going to be on a subpath of your domain, for example: `name.github.io/repo`
	// You can provide a url_prefix here to make the paths line up, if your docs will be at the root of the domain, leave this out.
	"url_prefix": "/repo",
	// This is where you define collections, you will probably have only one.
	"collections": {
		"foo": {
			"name": "foo",
			"source_url": "https://github.com/odin-lang/Odin/blob/main",
			// This URL is the prefix of your collection, core will be at /core, vendor at /vendor.
			// This is prefixed with the url_prefix field above if that is set.
			"base_url": "/foo",
			// The root of the project, because you will probably be in a subdirectory, you can use a relative path.
			// You can also use $ODIN_ROOT which is replaced by the directory that contains the Odin core and vendor collections.
			"root_path": "$ODIN_ROOTfoo",
			"license": {
				"text": "BSD-3-Clause",
				"url": "https://github.com/odin-lang/Odin/tree/master/LICENSE"
			},
			// Configuration for the home page.
			"home": {
				"title": "Foo",
				// The program can turn a readme into HTML and put it on the homepage.
				// The first h1 it finds will be replaced by one with a link and the title above.
				// You can leave this empty and provide a "description" instead.
				"embed_readme": "../../README.md",
				// Instead of embedding the readme, you can provide a simple description.
				"description": "Hello Foo!"
			}
		}
	}
}
```

### Deploying to GitHub pages using a workflow

You can automatically generate and publish your documentation to GitHub pages.

The only thing you need to configure in GitHub is enabling pages, go to your repo -> settings -> pages
and enable it, select GitHub actions as the deploy method.

Here is an example configuration, this goes at `.github/workflows/docs.yml`:

```yml
name: Deploy docs to GitHub pages

# Sets up to deploy when a new commit is pushed to the main branch, or when you click
# run in the GitHub UI.
on:
  push:
    branches: [main]
  workflow_dispatch:

# Upgrade permissions of this workflow to being able to upload to GitHub pages.
permissions:
  contents: read
  pages: write
  id-token: write

# Makes sure there is only one deployment running at a time.
concurrency:
  group: "pages"
  cancel-in-progress: true

jobs:
  docs:
    # Environment that the action deploys to.
    environment:
      name: github-pages
      url: ${{ steps.deployment.outputs.page_url }}

    runs-on: ubuntu-latest
    steps:
      - name: Setup Odin
        run: |
          sudo apt-get install llvm-14 clang-14
          cd /home/runner
          git clone https://github.com/odin-lang/Odin
          cd Odin
          make
          echo "/home/runner/Odin" >> $GITHUB_PATH

      - name: Get commonmark
        run: sudo apt-get install libcmark-dev

      - name: Get and build Odin docs generator
        run: |
          cd /home/runner
          git clone https://github.com/odin-lang/pkg.odin-lang.org odin-doc
          cd odin-doc
          # The /home/runner/odin directory is in the PATH so output it there.
          odin build . -out:/home/runner/odin/odin-doc
          cd /home/runner

      - uses: actions/checkout@v1

      - name: Generate documentation
        run: |
          cd website

          rm -rf static
          mkdir static

          # Generate the .odin-doc file.
          odin doc path-to-all.odin -file -all-packages -doc-format

          cd static

          # Generate the website using the .odin-doc and the custom configuration.
          odin-doc path-to-all.odin-doc path-to-config.json

          # A requirement for GitHub pages with custom domains.
          echo "your-custom-domain.example.com" > CNAME

      - uses: actions/configure-pages@v3

      - uses: actions/upload-pages-artifact@v2
        with:
          # This should point where you ran the generator.
          path: ./website/static

      - uses: actions/deploy-pages@v2
        id: deployment
```
