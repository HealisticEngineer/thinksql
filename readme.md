# ThinkSQL - SQL Processor as a Shared Library in Go
This project provides a SQL processor that can be used as a shared library in Go. It allows you to execute SQL queries and retrieve results.
# Requirements
- Go 1.18 or later
- C compiler (for building the shared library) recommended: https://jmeubank.github.io/tdm-gcc/
- winget install -e --id LLVM.LLVM
- winget install -e --id GnuWin32.Make
- winget install -e --id BrechtSanders.WinLibs.MCF.UCRT

# How to Build
``` $env:CGO_ENABLED = "1"; go build -buildmode=c-shared -ldflags="-s -w" -o ThinkSQL.dll main.go ```