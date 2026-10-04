# Third-party notices

Jeste's art, pixel font, music, sound effects, levels and story are original. They are
generated from code in this repository (`tools/gen_art.gd`, `tools/gen_audio.py`) or
written by hand (`data/`). No third-party art, fonts, samples or music are included.

The following third-party software is used.

## Godot Engine (MIT)

Jeste runs on [Godot Engine](https://godotengine.org). Release builds contain the Godot
runtime.

```
Copyright (c) 2014-present Godot Engine contributors (see AUTHORS.md).
Copyright (c) 2007-2014 Juan Linietsky, Ariel Manzur.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

The Godot runtime bundles third-party libraries under their own licenses. These include
FreeType, ENet, mbedTLS, libogg/libvorbis and zlib. The full list is in Godot's
[COPYRIGHT.txt](https://github.com/godotengine/godot/blob/master/COPYRIGHT.txt).
Portions of this software are copyright © The FreeType Project (www.freetype.org).
All rights reserved.

## Player controller reference (MIT)

The movement constants and timings in `scripts/sim/world.gd` follow a player controller
class whose source its authors published under the MIT license at
<https://github.com/NoelFB/Celeste> (`Source/Player/Player.cs`). They cover gravity, run
and air acceleration, jump and dash speeds, coyote time, jump buffering, climbing stamina
and corner correction. Jeste's simulation is its own GDScript implementation that reuses
those published values. None of that commercial game's assets, characters, music or names
are used.

```
MIT License

Copyright (c) 2018 Noel Berry

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Build-time tools (not redistributed)

- [NumPy](https://numpy.org) (BSD-3-Clause) synthesizes the audio in `tools/gen_audio.py`.
- [FFmpeg](https://ffmpeg.org) (LGPL/GPL) with libvorbis encodes the music to Ogg and
  assembles the trailer (`tools/trailer/make_trailer.py`). Only its output is included.
