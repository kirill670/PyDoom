#!python3
#cython: language_level=3

# Copyright (c) 2016, Kate Fox
# All rights reserved.
#
# This file is covered by the 3-clause BSD license.
# See the LICENSE file in this program's distribution for details.

# This module is responsible for reading and parsing Doom WAD (Where's All the Data?)
# files. WAD files are archives containing all game assets like graphics, maps,
# sounds, music, etc.

from cpython.mem cimport PyMem_Malloc, PyMem_Free
from libc.stdio cimport SEEK_SET, FILE, fopen, fread, fclose, fseek, sscanf
from libc.string cimport strcasecmp, memset, strncpy
import struct # Required for unpacking binary data

# --- Core Map Element Data Structures ---

cdef class WadVertex:
    cdef public short x, y

    def __init__(self, short x, short y):
        self.x = x
        self.y = y

    def __repr__(self):
        return f"<WadVertex x={self.x}, y={self.y}>"

cdef class WadSector:
    cdef public short floor_height, ceiling_height
    cdef public char[9] floor_texture_name, ceiling_texture_name # Null-terminated
    cdef public short light_level
    cdef public short special_type, tag_number

    def __init__(self, short floor_height, short ceiling_height, bytes floor_texture_name_b, bytes ceiling_texture_name_b, short light_level, short special_type, short tag_number):
        self.floor_height = floor_height
        self.ceiling_height = ceiling_height
        strncpy(self.floor_texture_name, floor_texture_name_b[:8], 8)
        self.floor_texture_name[8] = b'\0' # Ensure null termination
        strncpy(self.ceiling_texture_name, ceiling_texture_name_b[:8], 8)
        self.ceiling_texture_name[8] = b'\0' # Ensure null termination
        self.light_level = light_level
        self.special_type = special_type
        self.tag_number = tag_number

    @property
    def floor_texture(self):
        return self.floor_texture_name.decode('ascii', errors='ignore').rstrip('\x00')

    @property
    def ceiling_texture(self):
        return self.ceiling_texture_name.decode('ascii', errors='ignore').rstrip('\x00')

    def __repr__(self):
        return f"<WadSector floor_h={self.floor_height} ceil_h={self.ceiling_height} floor_tex='{self.floor_texture}' ceil_tex='{self.ceiling_texture}' light={self.light_level} special={self.special_type} tag={self.tag_number}>"

cdef class WadSidedef:
    cdef public short x_offset, y_offset
    cdef public char[9] upper_texture_name, lower_texture_name, middle_texture_name # Null-terminated
    cdef public short sector_index # Index into the list of sectors for this map
    cdef public WadSector sector # Direct reference to the WadSector object (linked later)

    def __init__(self, short x_offset, short y_offset, bytes upper_texture_name_b, bytes lower_texture_name_b, bytes middle_texture_name_b, short sector_index):
        self.x_offset = x_offset
        self.y_offset = y_offset
        strncpy(self.upper_texture_name, upper_texture_name_b[:8], 8)
        self.upper_texture_name[8] = b'\0'
        strncpy(self.lower_texture_name, lower_texture_name_b[:8], 8)
        self.lower_texture_name[8] = b'\0'
        strncpy(self.middle_texture_name, middle_texture_name_b[:8], 8)
        self.middle_texture_name[8] = b'\0'
        self.sector_index = sector_index
        self.sector = None # This will be linked by WadMapData.link_map_elements()

    @property
    def upper_texture(self):
        return self.upper_texture_name.decode('ascii', errors='ignore').rstrip('\x00')

    @property
    def lower_texture(self):
        return self.lower_texture_name.decode('ascii', errors='ignore').rstrip('\x00')

    @property
    def middle_texture(self):
        return self.middle_texture_name.decode('ascii', errors='ignore').rstrip('\x00')

    def __repr__(self):
        return f"<WadSidedef x_ofs={self.x_offset} y_ofs={self.y_offset} upper='{self.upper_texture}' lower='{self.lower_texture}' mid='{self.middle_texture}' sector_idx={self.sector_index}>"

cdef class WadLinedef:
    cdef public short start_vertex_index, end_vertex_index
    cdef public short flags
    cdef public short special_type
    cdef public short sector_tag
    cdef public short right_sidedef_index, left_sidedef_index # -1 indicates no sidedef

    cdef public WadVertex start_vertex, end_vertex # Direct references (linked later)
    cdef public WadSidedef right_sidedef, left_sidedef # Direct references (linked later)

    def __init__(self, short start_vertex_index, short end_vertex_index, short flags, short special_type, short sector_tag, short right_sidedef_index, short left_sidedef_index):
        self.start_vertex_index = start_vertex_index
        self.end_vertex_index = end_vertex_index
        self.flags = flags
        self.special_type = special_type
        self.sector_tag = sector_tag
        self.right_sidedef_index = right_sidedef_index
        self.left_sidedef_index = left_sidedef_index
        self.start_vertex = None
        self.end_vertex = None
        self.right_sidedef = None
        self.left_sidedef = None

    def __repr__(self):
        return f"<WadLinedef v_start_idx={self.start_vertex_index} v_end_idx={self.end_vertex_index} flags={self.flags} special={self.special_type} tag={self.sector_tag} right_sd_idx={self.right_sidedef_index} left_sd_idx={self.left_sidedef_index}>"

cdef class WadThing:
    cdef public short x, y, angle
    cdef public short thing_type
    cdef public short flags

    def __init__(self, short x, short y, short angle, short thing_type, short flags):
        self.x = x
        self.y = y
        self.angle = angle
        self.thing_type = thing_type
        self.flags = flags

    def __repr__(self):
        return f"<WadThing x={self.x} y={self.y} angle={self.angle} type={self.thing_type} flags={self.flags}>"

cdef class WadMapData:
    cdef public str map_name
    cdef public list vertices
    cdef public list sidedefs
    cdef public list linedefs
    cdef public list sectors
    cdef public list things

    def __init__(self, str map_name_str):
        self.map_name = map_name_str
        self.vertices = []
        self.sidedefs = []
        self.linedefs = []
        self.sectors = []
        self.things = []

    def link_map_elements(self):
        for sidedef_obj in self.sidedefs:
            if 0 <= sidedef_obj.sector_index < len(self.sectors):
                sidedef_obj.sector = self.sectors[sidedef_obj.sector_index]

        for linedef_obj in self.linedefs:
            if 0 <= linedef_obj.start_vertex_index < len(self.vertices):
                linedef_obj.start_vertex = self.vertices[linedef_obj.start_vertex_index]

            if 0 <= linedef_obj.end_vertex_index < len(self.vertices):
                linedef_obj.end_vertex = self.vertices[linedef_obj.end_vertex_index]

            if linedef_obj.right_sidedef_index != -1:
                if 0 <= linedef_obj.right_sidedef_index < len(self.sidedefs):
                    linedef_obj.right_sidedef = self.sidedefs[linedef_obj.right_sidedef_index]

            if linedef_obj.left_sidedef_index != -1:
                if 0 <= linedef_obj.left_sidedef_index < len(self.sidedefs):
                    linedef_obj.left_sidedef = self.sidedefs[linedef_obj.left_sidedef_index]

    def __repr__(self):
        return f"<WadMapData name='{self.map_name}' verts={len(self.vertices)} lines={len(self.linedefs)} sides={len(self.sidedefs)} sectors={len(self.sectors)} things={len(self.things)}>"

# --- End of Core Map Element Data Structures ---

# --- Texture and Patch Data Structures ---

cdef class WadPatchInfo:
    # Basic info about a patch, primarily its name as listed in PNAMES.
    # Width and height would typically be read from the patch lump itself when rendering.
    cdef public str name
    # cdef public int width, height # Optional: can be populated if patches are pre-scanned

    def __init__(self, str name):
        self.name = name

    def __repr__(self):
        return f"<WadPatchInfo name='{self.name}'>"

cdef class WadTexturePatch:
    # Represents a single patch within a composite texture definition.
    cdef public short origin_x, origin_y # Offset within the texture
    cdef public short patch_index        # Index into the PNAMES lump / list of patch names
    cdef public short stepdir            # Unused in Doom, for Strife compatibility
    cdef public short colormap           # Unused in Doom, for Strife compatibility
    # cdef public WadPatchInfo patch_info # Optional: Direct link to a WadPatchInfo if PNAMES is pre-parsed into those

    def __init__(self, short origin_x, short origin_y, short patch_index, short stepdir, short colormap):
        self.origin_x = origin_x
        self.origin_y = origin_y
        self.patch_index = patch_index
        self.stepdir = stepdir
        self.colormap = colormap

    def __repr__(self):
        return f"<WadTexturePatch origin=({self.origin_x},{self.origin_y}) patch_idx={self.patch_index}>"

cdef class WadTextureDefinition:
    # Represents a composite wall texture from TEXTURE1 or TEXTURE2 lumps.
    cdef public char[9] name_bytes # Null-terminated raw name
    cdef public bint masked # Not used in TEXTUREx, but part of maptexture_t in Doom source
    cdef public short width, height
    cdef public list patches # List of WadTexturePatch objects
    # cdef public int columndirectory # Obsolete, was for precompiled column data

    def __init__(self, bytes name_b, short width, short height, list patches_list, bint masked=False):
        strncpy(self.name_bytes, name_b[:8], 8)
        self.name_bytes[8] = b'\0'
        self.masked = masked # Typically False for wall textures from TEXTUREx
        self.width = width
        self.height = height
        self.patches = patches_list if patches_list is not None else []

    @property
    def name(self):
        return self.name_bytes.decode('ascii', errors='ignore').rstrip('\x00')

    def __repr__(self):
        return f"<WadTextureDefinition name='{self.name}' width={self.width} height={self.height} num_patches={len(self.patches)}>"

cdef class WadFlatTextureInfo:
    # Represents a flat texture (floor/ceiling).
    # Flats are simple 64x64 raw pixel data lumps.
    cdef public str name
    cdef public WadEntry lump_entry # Reference to the actual lump for data access

    def __init__(self, str name, WadEntry lump_entry_ref):
        self.name = name
        self.lump_entry = lump_entry_ref

    def __repr__(self):
        return f"<WadFlatTextureInfo name='{self.name}'>"

# --- End of Texture and Patch Data Structures ---

cdef enum namespaces:
    NS_GLOBAL = 0
    NS_SPRITES = 1
    NS_FLATS = 2

class BadWad (Exception):
    """This exception is returned to indicate the file is not a valid wad."""
    pass

def is_wadfile (filename_str):
    """is_wadfile (filename_str) -> bool
    
    Returns True if the file is a wad file."""
    
    encodedfn = filename_str.encode ("utf8")
    
    cdef const char *fn_c = encodedfn
    cdef char[4] magic_bytes
    cdef FILE *f_ptr = NULL
    
    f_ptr = fopen (fn_c, "rb")
    
    if not f_ptr:
        raise IOError ("Could not open " + filename_str)
    
    fread (magic_bytes, 1, 4, f_ptr)
    fclose (f_ptr)
    
    if ((magic_bytes[0] == b"I" or magic_bytes[0] == b"P") and magic_bytes[1] == b"W" and
    magic_bytes[2] == b"A" and magic_bytes[3] == b"D"):
        return True
    
    return False

cdef class WadEntry:
    cdef int _index
    cdef char[9] _name_bytes
    cdef int _namespace
    cdef size_t _size

    cdef size_t _pos
    cdef char *_data_ptr
    cdef bint _data_filled
    cdef FILE *_fileno_ptr

    @property
    def name(self):
        return self._name_bytes.decode('ascii', errors='ignore').rstrip('\x00')

    @property
    def index(self):
        return self._index

    @property
    def namespace(self):
        return self._namespace

    @property
    def size(self):
        return self._size

    @property
    def position(self):
        return self._pos
    
    def __cinit__ (self, size_t lump_size):
        self._size = lump_size
        self._data_ptr = <char *>PyMem_Malloc (self._size if self._size > 0 else 1)
        if self._data_ptr == NULL and self._size > 0:
            raise MemoryError("Failed to allocate memory for WadEntry data")
        self._data_filled = False
        memset(self._name_bytes, 0, 9)
        self._fileno_ptr = NULL

    def __dealloc__ (self):
        PyMem_Free (self._data_ptr)
    
    cdef void _set_info(self, int idx, const char* name_cstr, size_t file_pos, FILE* file_handle):
        self._index = idx
        strncpy(self._name_bytes, name_cstr, 8)
        self._name_bytes[8] = b'\0'
        self._pos = file_pos
        self._fileno_ptr = file_handle

    cdef void _set_namespace(self, int ns_val):
        self._namespace = ns_val

    def read_data(self):
        if self._data_filled:
            return self._data_ptr[0:self._size]
        
        if not self._fileno_ptr:
            raise ValueError ("Wad file pointer is not set for this entry, cannot read data.")
        
        if self._size == 0:
            self._data_filled = True
            return b""

        fseek (self._fileno_ptr, self._pos, SEEK_SET)
        cdef size_t bytes_read = fread (self._data_ptr, 1, self._size, self._fileno_ptr)
        
        if bytes_read != self._size:
            raise IOError(f"Error reading lump {self.name}: expected {self._size} bytes, got {bytes_read}")

        self._data_filled = True
        return self._data_ptr[0:self._size]

    def __repr__(self):
        return f"<WadEntry name='{self.name}' size={self.size} namespace={self.namespace} index={self.index}>"

cdef class WadFile:
    cdef list _entries_list
    cdef FILE *_file_handle_c
    cdef dict _parsed_maps_dict
    cdef list _pnames_list # List of patch names (strings)
    cdef dict _texture_definitions_dict # Dict of WadTextureDefinition objects
    cdef dict _flat_textures_dict # Dict of WadFlatTextureInfo objects or WadEntry references

    # --- Map Parsing Methods ---
    # Helper method to find the index of a named lump starting from a given index.
    # This is crucial because map lumps must follow their map marker (e.g., MAP01)
    # but their order isn't strictly guaranteed after that marker by all WAD editors.
    cdef int _find_map_lump_index(self, str lump_name_to_find, int start_search_index, str map_name_for_error):
        cdef WadEntry entry_obj
        cdef int map_marker_index = -1
        cdef int next_map_marker_index = len(self._entries_list)
        cdef int lump_to_find_index = -1

        # First, confirm the map_name_for_error itself is a valid marker
        # and find its index to establish the search range.
        temp_map_marker_entry = self.find_first_lump(map_name_for_error)
        if not temp_map_marker_entry:
            raise ValueError(f"Map marker lump {map_name_for_error} not found in WAD.")
        map_marker_index = temp_map_marker_entry.index

        # Determine the end of the search range (next map marker or end of WAD)
        for i in range(map_marker_index + 1, len(self._entries_list)):
            entry_obj = self._entries_list[i]
            # Check if it's a map marker (e.g., MAPxx, ExMx)
            if (entry_obj.name.startswith("MAP") and entry_obj.name[3:].isdigit()) or \
               (entry_obj.name.startswith("E") and entry_obj.name[1:].isdigit() and entry_obj.name[2] == "M" and entry_obj.name[3:].isdigit()):
                if entry_obj.size == 0: # Map markers are zero-length lumps
                    next_map_marker_index = i
                    break
        
        # Search for the target lump within the determined range
        for i in range(map_marker_index + 1, next_map_marker_index):
            entry_obj = self._entries_list[i]
            if entry_obj.name == lump_name_to_find:
                lump_to_find_index = i
                break
        
        if lump_to_find_index == -1:
            # It's possible some optional lumps like REJECT or BLOCKMAP might be missing.
            # For essential lumps, this indicates an issue.
            # For now, we'll raise an error for any missing lump we actively seek.
            raise ValueError(f"Lump {lump_name_to_find} for map {map_name_for_error} not found within expected range.")

        return lump_to_find_index

    cdef void _parse_vertices_lump(self, WadEntry lump_entry, WadMapData current_map_data):
        vertex_data_bytes = lump_entry.read_data()
        cdef int num_vertices = len(vertex_data_bytes) // 4 # Each vertex is 2 shorts (4 bytes)
        cdef short x, y
        for i in range(num_vertices):
            offset = i * 4
            # Format is '<hh' for two little-endian shorts
            x, y = struct.unpack_from("<hh", vertex_data_bytes, offset)
            current_map_data.vertices.append(WadVertex(x, y))

    cdef void _parse_sectors_lump(self, WadEntry lump_entry, WadMapData current_map_data):
        sector_data_bytes = lump_entry.read_data()
        cdef int num_sectors = len(sector_data_bytes) // 26 # Each sector is 26 bytes
        cdef short floor_h, ceil_h, light, special, tag
        cdef bytes floor_tex_b, ceil_tex_b
        for i in range(num_sectors):
            offset = i * 26
            # Format: <hh8s8shhh  (2 shorts, 2x 8-char strings, 3 shorts)
            floor_h, ceil_h, floor_tex_b, ceil_tex_b, light, special, tag = struct.unpack_from("<hh8s8shhh", sector_data_bytes, offset)
            current_map_data.sectors.append(WadSector(floor_h, ceil_h, floor_tex_b, ceil_tex_b, light, special, tag))

    cdef void _parse_sidedefs_lump(self, WadEntry lump_entry, WadMapData current_map_data):
        sidedef_data_bytes = lump_entry.read_data()
        cdef int num_sidedefs = len(sidedef_data_bytes) // 30 # Each sidedef is 30 bytes
        cdef short x_ofs, y_ofs, sec_idx
        cdef bytes upper_b, lower_b, middle_b
        for i in range(num_sidedefs):
            offset = i * 30
            # Format: <hh8s8s8sh (2 shorts, 3x 8-char strings, 1 short for sector_index)
            x_ofs, y_ofs, upper_b, lower_b, middle_b, sec_idx = struct.unpack_from("<hh8s8s8sh", sidedef_data_bytes, offset)
            current_map_data.sidedefs.append(WadSidedef(x_ofs, y_ofs, upper_b, lower_b, middle_b, sec_idx))

    cdef void _parse_linedefs_lump(self, WadEntry lump_entry, WadMapData current_map_data):
        linedef_data_bytes = lump_entry.read_data()
        # Standard Doom linedef is 14 bytes. Hexen format has an extra byte for args.
        # Assuming standard Doom format here.
        cdef int num_linedefs = len(linedef_data_bytes) // 14
        cdef short v_start, v_end, flags, special, tag, side_right, side_left
        for i in range(num_linedefs):
            offset = i * 14
            # Format: <hhhhhhh (7 shorts)
            v_start, v_end, flags, special, tag, side_right, side_left = struct.unpack_from("<hhhhhhh", linedef_data_bytes, offset)
            current_map_data.linedefs.append(WadLinedef(v_start, v_end, flags, special, tag, side_right, side_left))

    cdef void _parse_things_lump(self, WadEntry lump_entry, WadMapData current_map_data):
        thing_data_bytes = lump_entry.read_data()
        cdef int num_things = len(thing_data_bytes) // 10 # Each thing is 10 bytes
        cdef short x, y, angle, type_val, flags
        for i in range(num_things):
            offset = i * 10
            # Format: <hhhhh (5 shorts)
            x, y, angle, type_val, flags = struct.unpack_from("<hhhhh", thing_data_bytes, offset)
            current_map_data.things.append(WadThing(x, y, angle, type_val, flags))

    @property
    def entries(self):
        return self._entries_list[:]

    def __cinit__ (self, filename_str):
        cdef const char *fn_c = NULL

        encodedfn = filename_str.encode ("utf8")
        fn_c = encodedfn

        self._file_handle_c = NULL
        self._file_handle_c = fopen (fn_c, "rb")
        self._parsed_maps_dict = {}
        self._entries_list = []
        self._pnames_list = []
        self._texture_definitions_dict = {}
        self._flat_textures_dict = {}

    def __dealloc__ (self):
        cdef WadEntry entry_obj
        for entry_obj in self._entries_list:
            entry_obj._fileno_ptr = NULL

        if self._file_handle_c != NULL:
            fclose (self._file_handle_c)
    
    def __init__ (self, filename_str):
        cdef int current_namespace = NS_GLOBAL
        cdef char[4] magic_bytes
        cdef unsigned char[8] header_bytes
        cdef bint is_bad_magic = True
        
        cdef int num_lumps = 0
        cdef int info_table_offset = 0
        cdef unsigned char[4] lump_pos_bytes
        cdef size_t lump_pos_val = 0
        cdef unsigned char[4] lump_size_bytes
        cdef size_t lump_size_val = 0
        cdef char[9] lump_name_cstr
        cdef WadEntry current_dir_entry = None
        
        cdef (const char *)[4] MARKER_NAMES = (
            b"S_START", b"S_END",
            b"F_START", b"F_END"
        )
        cdef bint[4] IS_START_MARKER = (True, False, True, False)
        cdef int[4] MARKER_NAMESPACE_TYPE = (NS_SPRITES, NS_SPRITES, NS_FLATS, NS_FLATS)
        
        if self._file_handle_c == NULL:
            raise IOError ("Could not open " + filename_str + " for reading")
        
        memset (magic_bytes, 0, 4)
        fread (magic_bytes, 1, 4, self._file_handle_c)
        
        if ((magic_bytes[0] == b"I" or magic_bytes[0] == b"P") and magic_bytes[1] == b"W" and
        magic_bytes[2] == b"A" and magic_bytes[3] == b"D"):
            is_bad_magic = False
        
        if is_bad_magic:
            raise BadWad ("Magic doesn't correspond to any known wad file type")
        
        memset (header_bytes, 0, 8)
        fread (header_bytes, 1, 8, self._file_handle_c)

        num_lumps  = header_bytes[0]
        num_lumps |= header_bytes[1] << 8
        num_lumps |= header_bytes[2] << 16
        num_lumps |= header_bytes[3] << 24
        
        info_table_offset  = header_bytes[4]
        info_table_offset |= header_bytes[5] << 8
        info_table_offset |= header_bytes[6] << 16
        info_table_offset |= header_bytes[7] << 24
        
        fseek (self._file_handle_c, info_table_offset, SEEK_SET)
        
        for lump_idx in range (num_lumps):
            memset (lump_pos_bytes, 0, 4)
            memset (lump_size_bytes, 0, 4)
            memset (lump_name_cstr, 0, 9)
            
            fread (lump_pos_bytes, 1, 4, self._file_handle_c)
            lump_pos_val  = lump_pos_bytes[0]
            lump_pos_val |= lump_pos_bytes[1] << 8
            lump_pos_val |= lump_pos_bytes[2] << 16
            lump_pos_val |= lump_pos_bytes[3] << 24
            
            fread (lump_size_bytes, 1, 4, self._file_handle_c)
            lump_size_val  = lump_size_bytes[0]
            lump_size_val |= lump_size_bytes[1] << 8
            lump_size_val |= lump_size_bytes[2] << 16
            lump_size_val |= lump_size_bytes[3] << 24
            
            fread (lump_name_cstr, 1, 8, self._file_handle_c)
            lump_name_cstr[8] = b'\0'
            
            current_dir_entry = WadEntry (lump_size_val)
            current_dir_entry._set_info(lump_idx, lump_name_cstr, lump_pos_val, self._file_handle_c)
            
            is_this_lump_a_marker = False
            for i in range(4):
                if not strcasecmp (current_dir_entry._name_bytes, MARKER_NAMES[i]):
                    new_namespace_after_marker = NS_GLOBAL
                    if IS_START_MARKER[i]:
                        new_namespace_after_marker = MARKER_NAMESPACE_TYPE[i]

                    current_dir_entry._set_namespace(new_namespace_after_marker if lump_size_val > 0 and IS_START_MARKER[i] else NS_GLOBAL)
                    current_namespace = new_namespace_after_marker
                    is_this_lump_a_marker = True
                    break
            
            if not is_this_lump_a_marker:
                current_dir_entry._set_namespace(current_namespace)
            
            self._entries_list.append (current_dir_entry)

        # After reading all lumps, parse PNAMES and TEXTUREx if they exist
        pnames_lump = self.find_first_lump("PNAMES")
        if pnames_lump:
            self._parse_pnames_lump(pnames_lump)
        else:
            # PNAMES is essential for TEXTUREx lumps. Log a warning if TEXTUREx lumps are present without PNAMES.
            if self.find_first_lump("TEXTURE1") or self.find_first_lump("TEXTURE2"):
                # Consider logging a warning here using Python's logging module if available
                # For now, just pass or print a basic warning.
                print("Warning: TEXTURE1/TEXTURE2 lumps found but PNAMES is missing.")
            pass

        texture1_lump = self.find_first_lump("TEXTURE1")
        if texture1_lump:
            self._parse_texture_lump(texture1_lump)

        texture2_lump = self.find_first_lump("TEXTURE2")
        if texture2_lump:
            self._parse_texture_lump(texture2_lump) # Same parser can handle both

        self._catalog_flat_textures()

    cdef void _catalog_flat_textures(self):
        f_start_lump = self.find_first_lump("F_START")
        f_end_lump = self.find_first_lump("F_END")

        if not f_start_lump or not f_end_lump:
            # F_START or F_END missing, cannot catalog flats. This might be normal for some WADs (e.g. only maps).
            # print("Warning: F_START or F_END lump not found. Cannot catalog flat textures.")
            return

        # We need to find the index of F_START and F_END to iterate correctly.
        # This assumes _entries_list is sorted by lump index, which it is.
        f_start_idx = -1
        f_end_idx = -1

        cdef WadEntry temp_entry
        for i in range(len(self._entries_list)):
            temp_entry = self._entries_list[i]
            if temp_entry.name == "F_START":
                f_start_idx = i
            elif temp_entry.name == "F_END":
                f_end_idx = i
                break # F_END found, no need to search further
        
        if f_start_idx == -1 or f_end_idx == -1 or f_start_idx >= f_end_idx:
            # print("Warning: Valid F_START/F_END range not found for flat cataloging.")
            return

        # Iterate from the lump *after* F_START up to (but not including) F_END
        cdef WadEntry flat_lump_entry
        for i in range(f_start_idx + 1, f_end_idx):
            flat_lump_entry = self._entries_list[i]
            # Flats are typically 4096 bytes (64x64 raw pixels), but other sizes can exist.
            # We should catalog any non-zero size lump within this section as a potential flat.
            # The namespace check is an alternative or additional check.
            if flat_lump_entry.size > 0: # and flat_lump_entry.namespace == NS_FLATS:
                # Use Python string for dict key, cleaned and upper-cased as per Doom convention
                clean_flat_name = flat_lump_entry.name.upper() # Flat names are significant as is
                if clean_flat_name:
                    self._flat_textures_dict[clean_flat_name] = WadFlatTextureInfo(clean_flat_name, flat_lump_entry)

    cdef void _parse_pnames_lump(self, WadEntry pnames_lump):
        data = pnames_lump.read_data()
        cdef int num_patches = struct.unpack_from("<i", data, 0)[0]
        cdef int offset = 4
        cdef bytes patch_name_raw # Changed from char[9] to bytes for direct slicing
        for i in range(num_patches):
            patch_name_raw = data[offset:offset+8]
            self._pnames_list.append(patch_name_raw.decode('ascii', errors='ignore').upper().rstrip('\x00'))
            offset += 8

    cdef void _parse_texture_lump(self, WadEntry texture_lump):
        texture_data_bytes = texture_lump.read_data()
        cdef int num_textures = struct.unpack_from("<i", texture_data_bytes, 0)[0]
        cdef int current_offset = 4
        cdef list texture_offsets = []
        for i in range(num_textures):
            texture_offsets.append(struct.unpack_from("<i", texture_data_bytes, current_offset)[0])
            current_offset += 4

        for tex_offset in texture_offsets:
            tex_name_b, tex_masked_unused, tex_width, tex_height, tex_coldir_unused, tex_patchcount = struct.unpack_from("<8sihhih", texture_data_bytes, tex_offset)

            patches_list = []
            patch_offset_in_tex_def = tex_offset + 22

            for p in range(tex_patchcount):
                p_origin_x, p_origin_y, p_patch_idx, p_stepdir, p_colormap = struct.unpack_from("<hhhhh", texture_data_bytes, patch_offset_in_tex_def)
                patches_list.append(WadTexturePatch(p_origin_x, p_origin_y, p_patch_idx, p_stepdir, p_colormap))
                patch_offset_in_tex_def += 10

            tex_def = WadTextureDefinition(tex_name_b, tex_width, tex_height, patches_list)
            clean_tex_name = tex_name_b.decode('ascii', errors='ignore').upper().rstrip('\x00')
            if clean_tex_name:
                self._texture_definitions_dict[clean_tex_name] = tex_def

    def find_first_lump (self, lump_name_str):
        if type(lump_name_str) != bytes:
            encoded_name = lump_name_str.encode ("ascii", errors="ignore")
        else:
            encoded_name = lump_name_str
        
        cdef char[9] search_name_c
        strncpy(search_name_c, encoded_name, 8)
        search_name_c[8] = b'\0'

        cdef WadEntry entry_obj
        for entry_obj in self._entries_list:
            if not strcasecmp (search_name_c, entry_obj._name_bytes):
                return entry_obj
        return None
    
    def find_all_lumps (self, lump_name_str):
        if type(lump_name_str) != bytes:
            encoded_name = lump_name_str.encode ("ascii", errors="ignore")
        else:
            encoded_name = lump_name_str

        cdef char[9] search_name_c
        strncpy(search_name_c, encoded_name, 8)
        search_name_c[8] = b'\0'

        matches_list = []
        cdef WadEntry entry_obj
        for entry_obj in self._entries_list:
            if not strcasecmp (search_name_c, entry_obj._name_bytes):
                matches_list.append (entry_obj)
        return matches_list

    def get_map_names(self):
        cdef list map_names = []
        cdef WadEntry entry_obj
        for entry_obj in self._entries_list:
            # Standard map names: MAPxx (Doom 2, Final Doom), ExMx (Doom 1 / Ultimate Doom)
            is_doom2_map = entry_obj.name.startswith("MAP") and len(entry_obj.name) == 5 and entry_obj.name[3:].isdigit()
            is_doom1_map = len(entry_obj.name) == 4 and entry_obj.name.startswith("E") and entry_obj.name[1].isdigit() and entry_obj.name[2] == "M" and entry_obj.name[3].isdigit()
            if entry_obj.size == 0 and (is_doom2_map or is_doom1_map):
                map_names.append(entry_obj.name)
        return map_names
        
    def get_map_data(self, str map_name_str):
        if not map_name_str:
            raise ValueError("Map name cannot be empty.")

        if map_name_str in self._parsed_maps_dict:
            return self._parsed_maps_dict[map_name_str]

        # Ensure map_name_str is a valid map marker lump that exists
        map_header_lump = self.find_first_lump(map_name_str)
        if not map_header_lump or map_header_lump.size != 0:
            raise ValueError(f"Map {map_name_str} not found or is not a valid zero-size map header lump.")
        
        map_data_obj = WadMapData(map_name_str)
        
        # Find the map header lump index to start searching for other map lumps from there.
        map_header_lump_index = map_header_lump.index

        # Define the standard lumps that make up a map's structure
        # Order here matters for some WADs, but we search by name after the map marker.
        # We will parse them in a logical order for dependency (e.g., vertices before linedefs).
        map_lump_names = ["VERTEXES", "SECTORS", "SIDEDEFS", "LINEDEFS", "THINGS"]
        parsing_functions = {
            "VERTEXES": self._parse_vertices_lump,
            "SECTORS": self._parse_sectors_lump,
            "SIDEDEFS": self._parse_sidedefs_lump,
            "LINEDEFS": self._parse_linedefs_lump,
            "THINGS": self._parse_things_lump
        }

        cdef WadEntry specific_lump_entry
        cdef int specific_lump_idx

        for lump_to_parse_name in map_lump_names:
            try:
                # _find_map_lump_index is not strictly needed if we assume lumps are named uniquely after map header
                # and find_first_lump correctly scopes or we iterate from map_header_lump_index.
                # For simplicity, let's find the lump directly after the map header for now.
                # A more robust _find_map_lump_index would be needed if lump names are not unique across the WAD
                # or if we need to ensure they are within the specific map's section before the next map marker.

                # Find the lump by its name, starting search *after* the map header lump
                # This assumes that map-specific lumps are found after their header and before the next map's header.
                # This is a simplified search; a truly robust one would use _find_map_lump_index as sketched.
                found_lump = False
                cdef WadEntry entry_obj # Ensure entry_obj is declared in this scope
                for i in range(map_header_lump_index + 1, len(self._entries_list)):
                    entry_obj = self._entries_list[i]
                    if entry_obj.name == lump_to_parse_name:
                        specific_lump_entry = entry_obj
                        found_lump = True
                        break
                    # If another map marker is found before the lump, then it's missing for the current map.
                    is_next_doom2_map = entry_obj.name.startswith("MAP") and len(entry_obj.name) == 5 and entry_obj.name[3:].isdigit()
                    is_next_doom1_map = len(entry_obj.name) == 4 and entry_obj.name.startswith("E") and entry_obj.name[1].isdigit() and entry_obj.name[2] == "M" and entry_obj.name[3].isdigit()
                    if entry_obj.size == 0 and (is_next_doom2_map or is_next_doom1_map):
                        break # Stop searching if we hit the next map marker

                if not found_lump:
                    # Optional lumps like BLOCKMAP, REJECT might not be present. For essential ones, this is an error.
                    # For now, we require all listed map_lump_names to be present.
                    raise ValueError(f"Essential map lump {lump_to_parse_name} for map {map_name_str} not found.")

                parsing_func = parsing_functions[lump_to_parse_name]
                parsing_func(specific_lump_entry, map_data_obj)
            except Exception as e:
                # Propagate error with more context
                raise RuntimeError(f"Failed to parse lump {lump_to_parse_name} for map {map_name_str}: {e}")

        # After all individual components are loaded, link them (e.g., Sidedefs to Sectors)
        map_data_obj.link_map_elements()

        self._parsed_maps_dict[map_name_str] = map_data_obj
        return map_data_obj
```
