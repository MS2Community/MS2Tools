# MS2Tools
Each tool has a help text showing up when ran with no arguments, check it out!

The tools have no logic for handling low memory situations so make sure you have a decent amount of memory (RAM) free. I cannot help with anything related to "OutOfMemoryException" errors.

I recommend to use the provided powershell scripts (.ps1 files) (with the necessary personal edits) for each tool.
By default the scripts are made to use syncMode 0 (Sync) so if you want faster extraction/creation you must set it to Async or 1.

# Building

```
dotnet build MS2Tools.sln -c Release
```

That produces framework-dependent output and needs a .NET 8 runtime installed to run.

To produce standalone binaries that carry their own runtime, use `publish.sh`:

```
./publish.sh                          # publishes for the current machine
./publish.sh --rid linux-x64          # publishes for another architecture
./publish.sh --rid win-x64 --out dist
```

The binaries land in `publish/<rid>/` and need no installed .NET runtime.

## Why the publish is self-contained

MS2Lib compresses archive payloads with `System.IO.Compression.ZLibStream`. The .NET
documentation states that the exact compressed byte sequence is not a stable contract
and may change between releases. .NET 9 changed the deflate backend from zlib to
zlib-ng, so the same input compressed on .NET 9 or 10 does not have to produce the same
bytes as on .NET 8.

Archive bytes have to stay reproducible: a client is served archives built on whichever
machine happened to run the build, and the server ingests the same output. So the
projects stay on `net8.0` and the publish embeds the .NET 8 runtime, which pins the
deflate implementation instead of letting the binary roll forward onto whatever runtime
the machine has.

Architecture does not affect the output. `linux-arm64` and `linux-x64` builds of
MS2Create produce byte-identical `.m2d` and `.m2h` files from the same input.

## Checking that archive bytes still match

`determinism-check.sh` builds a few small folders from a LithMS2-XML checkout and
compares the result against recorded sha256 hashes:

```
./determinism-check.sh                       # uses publish/<rid>/MS2Create and ../LithMS2-XML
./determinism-check.sh --xml-repo /path/to/LithMS2-XML
```

It exits non-zero when the bytes differ, which means output from that build must not be
deployed. Each case is pinned to the commit that last changed its source folder, and a
case whose folder has moved on or has uncommitted edits is skipped rather than reported
as a mismatch.

# MS2Extract
This is what you need if you want to extract the files from the MapleStory 2 game archives!

```
Usage: MS2Extract.exe <source> <destination> [syncMode = Async] [logMode = Warning]
```

`<source>` and `<destination>` are required arguments while `[syncMode]` and `[logMode]` are optional and default to Async and Warning respectively.

`<source>` can be either:
* a directory: it will extract all MapleStory 2 game archives from that folder and all subfolders
* a file: it will extract only the specified file, you are not required to specify the extension so you can use either "Image", "Image.m2h" or "Image.m2d"

`<destination>` must be a folder, this is where the extracted files will be placed.

`[syncMode]` by default is Async. This has 2 different modes, Sync or Async or you can use 0 and 1 respectively. Sync will try to use less resources (CPU and RAM) while Async will use everything that it can get.

`[logMode]` is the logging level of the output produced by the application, you can use either names or numbers, the following are valid: Debug, Verbose, Info, Warning, Error; in the same order are also for the numbers: 0, 1, 2, 3, 4.

# MS2Create
This tool is for creating your own MapleStory 2 game archive!

```
Usage: MS2Create.exe <source> <destination> <archive name> <mode> [syncMode = Async] [logMode = Warning]
```

`<source>`, `<destination>`, `<archive name>` and <mode> are required arguments while `[syncMode]` and `[logMode]` are optional and default to Async and Warning respectively.

`<source>` must be a folder, all the files, folders and subfolders from the given folder will be in the archive.

`<destination>` must be a folder, this is where the created archive will be placed.

`<archive name>` is the name you want to give to the archive.

`<mode>` is the encryption mode for the archive. The supported modes are MS2F, NS2F, OS2F and PS2F or you can use 1177703245, 1177703246, 1177703247, 1177703248 respectively.

`[syncMode]` by default is Async. This has 2 different modes, Sync or Async or you can use 0 and 1 respectively. Sync will try to use less resources (CPU and RAM) while Async will use everything that it can get.

`[logMode]` is the logging level of the output produced by the application, you can use either names or numbers, the following are valid: Debug, Verbose, Info, Warning, Error; in the same order are also for the numbers: 0, 1, 2, 3, 4.


# MS2FileHeaderExporter
This is not important, it's just there for exporting some heading data of the archives. (debug stuff)
