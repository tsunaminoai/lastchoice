# LastChoice

## Description

LastChoice is a cli application to recover data from a FirstChoice database.

## Goals

- [x] Read a FirstChoice database
- [x] Read out to CSV
- [ ] Read out to JSON

## Usage

```bash
fzp (options) <path-to-database>
options:
-h display header information
-f display field information
-r display records
-c display records as CSV with header row
-o <path-to-output> write records to file at path
```

## Why?

While it may seem silly to have a tool to read a database that is no longer in use, I had a few reasons for doing so. My Dad got in on using computers for business and personal use way back in the late '80s. As a result, he had a lot of data in FirstChoice databases. When his old machine died, he asked if I could help recover the data in the `FOL` flies he had. I knew that other converters existed, but of these, one was a paid application, and the [other](https://github.com/alfille/firstchoice), while an invaluable resource, was not going to be simple enough for my dad to use.

I decided to write this tool to help him out. I also wanted to learn more about Zig, and this seemed like a good project to do so. More than that, I realized that there are probably more FOL files floating around iini people's basements and attics, and I wanted to make sure that there was a tool that could read them into an exensible format for data archeology.

If this tool has been of use to you, please let me know. I'd love to hear about it.
