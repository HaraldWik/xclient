# Xclient

## Goals
The goal is to have a _minimal_ xclient like xcb but for zig and **without** libc

## Installation
```sh
zig fetch --save git+https://github.com/HaraldWik/xclient
```

```zig
const xclient = b.dependency("xclient", .{ .target = target, .optimize = optimize }).module("xclient");
```
