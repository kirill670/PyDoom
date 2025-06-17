# Copyright (c) 2016, Kate Fox
# All rights reserved.
#
# This file is covered by the 3-clause BSD license.
# See the LICENSE file in this program's distribution for details.

# This module provides Python-level classes and functions for managing graphics-related
# data, primarily focused on Doom's specific formats like palettes and patch graphics.
# Some of this functionality is complemented or superseded by the Cython-based
# classes in `pydoom/interface.pyx` for performance-critical operations and
# direct OpenGL interaction.

from pydoom.video import ImageSurface
import io
import struct, array
import zlib

def PackColor (red, green, blue, alpha):
    x =   alpha & 0xFF
    x += (blue  & 0xFF) << 8
    x += (green & 0xFF) << 16
    x += (red   & 0xFF) << 24
    return x

def UnpackColor (color):
    red   = (color << 24) & 0xFF
    green = (color << 16) & 0xFF
    blue  = (color <<  8) & 0xFF
    alpha =  color        & 0xFF
    return (red, green, blue, alpha)

##### PALETTES #####

class PaletteIndex:
    # Represents a single RGB color entry within a 256-color palette.
    def __init__ (self, red, green, blue):
        self.red   = red
        self.green = green
        self.blue  = blue

    def __str__ (self):
        return "({0}, {1}, {2})".format (self.red, self.green,
            self.blue)

    def __bytes__ (self):
        return struct.pack ("<BBB", self.red, self.green, self.blue)

class Palette:
    # Represents a 256-color palette, typically loaded from a PLAYPAL lump.
    # Contains a list of PaletteIndex objects.
    def __init__ (self):
        self.colors = []

def MakePalettes (byteseq):
    # Parses a binary PLAYPAL lump (which can contain multiple palettes)
    # and returns a list of Palette objects.
    pals = []
    numpals = len (byteseq) // 768
    if len (byteseq) % 768 != 0:
        raise ValueError ("Passed a strange-size palette lump")

    pos = 0
    for i in range (numpals):
        pal = Palette ()

        for e in range (256):
            pal.colors.append (PaletteIndex (*struct.unpack ("<BBB",
                byteseq[pos:pos+3])))
            pos += 3

        pals.append (pal)

    return pals

##### IMAGES #####

class Image:
    # A Python-level class for representing an image, storing its data in an
    # RGBA buffer (delegated to an ImageSurface, likely from an earlier version
    # or for Python-side manipulation before passing to Cython/OpenGL).
    # For direct OpenGL texture preparation, `pydoom.interface.ImageSurface` is generally used.
    def __init__ (self, width, height, xofs=0, yofs=0):
        self.width = width
        self.height = height
        self.xoffset = xofs
        self.yoffset = yofs
        self.data = ImageSurface (width, height)

    def GetPixel (self, x, y):
        # Retrieves the RGBA color of a pixel.
        return UnpackColor (self.data.getPixel (x, y))

    def SetPixel (self, x, y, color=None):
        # Sets the RGBA color of a pixel.
        if x < 0 or x >= self.dimensions[0]:
            raise ValueError ("x is out of the image boundary ({} <> {})".format (x, self.dimensions[0]))
        if y < 0 or y >= self.dimensions[1]:
            raise ValueError ("y is out of the image boundary ({} <> {})".format (y, self.dimensions[1]))

        w = self.dimensions[0]
        if color is None:
            color = (0, 0, 0, 0)

        if type (color) is PaletteIndex:
            color = (color.red, color.green, color.blue, 255)

        self.data.setPixel (x, y, PackColor (*color))

    ### Image Readers ###

    @classmethod
    def LoadDoomGraphic (cls, bytebuffer, palette):
        # Loads a Doom patch graphic from its raw byte data and a Palette object.
        # Converts the indexed color data to RGBA and stores it in a new Image instance.
        # This is similar to `interface.pyx:ImageSurface.LoadDoomGraphic` but operates
        # with Python-level Palette objects.
        pos = 0

        width, height, xofs, yofs = struct.unpack_from ("<HHHH",
            bytebuffer, pos)
        pos += struct.calcsize ("<HHHH")

        image = cls (width, height, xofs, yofs)

        colheaders = []

        # The headers for each column
        for colheader in range (width):
            colheaders.append (struct.unpack_from ("<I", bytebuffer, pos)[0])
            pos += struct.calcsize ("<I")

        # Okay, so in the standard graphic format, if the last row
        # started in the same column is above or at the height last
        # drawn, they'd usually be drawn above or on top of the column
        # we just drew (which would be a waste of space since we're just
        # drawing on top of pixels we've *just* drawn).

        # Instead, what we do is *add* the last offset to our current
        # one, so we're always drawing in new space instead. This gives
        # us twice the column height to work with, allowing graphic
        # columns to start from up to the 512th row instead of the
        # 256th. This means transparent images that are > 256 in height
        # won't corrupt.

        for column in range (width):
            lastrowstart = -1
            rowstart = 0
            byteofs = colheaders[column]
            while True:
                rowstart = struct.unpack_from ("<B", bytebuffer,
                    byteofs)[0]
                byteofs += 1

                if rowstart == 255:
                    # No more pieces to draw, go to next column
                    break

                if rowstart <= lastrowstart:
                    rowstart += lastrowstart

                columnlength = struct.unpack_from ("<B", bytebuffer,
                    byteofs)[0]
                byteofs += 2

                for rowpos in range (columnlength):
                    palindex = struct.unpack_from ("<B", bytebuffer,
                        byteofs)[0]
                    byteofs += 1

                    palcolor = palette.colors[palindex]
                    image.SetPixel (column, rowpos + rowstart, palcolor)

                byteofs += 1
                lastrowstart = rowstart

        return image

    @classmethod
    def LoadPNG (cls, bytebuffer):
        # A partially implemented PNG loader at the Python level.
        # For more complete PNG loading, `pydoom.interface.ImageSurface.LoadPNG` is used.

        decompressor = zlib.decompressobj ()

        if bytebuffer[0:8] != b'\x89PNG\r\n\x1a\n':
            raise ValueError ("The PNG header is corrupted")

        # TODO
        pass
