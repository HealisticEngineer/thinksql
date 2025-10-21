# SQL Processor
This project provides a SQL processor that can be used as a shared library in Go. It allows you to execute SQL queries and retrieve results.
# Requirements
- Go 1.18 or later
- C compiler (for building the shared library) recommended: https://jmeubank.github.io/tdm-gcc/


# How to Build
``` $env:CGO_ENABLED=1; $env:GOARCH="amd64"; go build -o sqlprocessor.dll -buildmode=c-shared . ```
``` $env:CGO_ENABLED=1; $env:GOARCH="amd64"; go build -ldflags="-s -w" -o sqlprocessor.dll -buildmode=c-shared main.go ```