# PyDoom Project Documentation

This document provides an overview of the PyDoom project structure, implemented features, core classes, and a list of features to be implemented.

## 1. Project Structure and Core Modules

### 1.1. Directory Structure

The project is organized into the following main directories:

*   **`/` (Root Directory):** Contains main scripts like `pydoom.py` (the game's entry point), build scripts (`setup_exe.py`, `setup_extensions.py`), README, LICENSE, and the `DOCUMENTATION.md` file itself.
*   **`pydoom/`:** This is the core package for the PyDoom game engine. It contains Python and Cython modules responsible for various aspects of the game.
*   **`resourcezip/`:** Contains resources that are packaged into `PyDoomResource.zip`. This includes:
    *   `Games.txt`: A list of game modules to be loaded.
    *   `resources/`: Subdirectories for fonts, graphics (like logos, console background), and shaders.
    *   `scripts/`: Python modules that can define different games or game behaviors (e.g., `doom/`, `doom2/`).
*   **`extern/`:** Contains external libraries and their source code or binaries that PyDoom depends on.
    *   `SDL2-2.0.4/`: The Simple DirectMedia Layer library, used for windowing, input, and graphics context creation.
    *   `bass24/`: The BASS audio library, intended for sound and music playback (though not yet fully integrated).
*   **`testing/`:** Contains various image files presumably used for testing image loading capabilities.

### 1.2. Core Modules in `pydoom/`

The `pydoom/` directory houses the essential modules of the game engine:

*   **`pydoom.py`:**
    *   The main entry point for the PyDoom application.
    *   Initializes logging, parses command-line arguments, and loads the system configuration.
    *   Sets up the main resource archive (`PyDoomResource.zip`).
    *   Initializes the `OpenGLWindow` for display.
    *   Currently, it includes test code to load `doom2.wad`, display its `TITLEPIC`, and then exits.

*   **`arguments.py`:**
    *   Defines the `ArgumentParser` class.
    *   Responsible for parsing command-line arguments passed to the game (e.g., screen resolution, fullscreen mode, game selection, external WAD files).

*   **`configuration.py`:**
    *   Manages the game's configuration settings stored in `pydoom.ini`.
    *   Handles loading existing configurations and creating a default one if it doesn't exist.
    *   Currently supports video settings (fullscreen, width, height).

*   **`core.pyx`:**
    *   A Cython module intended to house the central game logic and core engine components (`PyDoomCore` class).
    *   Currently, it's mostly a placeholder and does not contain significant game logic.

*   **`graphics.py`:**
    *   Contains Python classes and functions for handling graphical data.
    *   `Palette` and `PaletteIndex`: Manage 256-color palettes, particularly for Doom's PLAYPAL lump.
    *   `Image`: A Python-level image class that was likely an earlier version or helper for image manipulation. It can load Doom graphics.
    *   Includes functions for packing/unpacking color values.
    *   Contains a partially implemented `LoadPNG` method within the `Image` class.

*   **`interface.pyx`:**
    *   A Cython module that serves as the bridge to SDL2 and OpenGL.
    *   `ImageSurface`: A Cython class for storing and manipulating raw image data (pixels). This is the primary class used for texture data passed to OpenGL. It includes methods to load Doom graphics (`LoadDoomGraphic`) and PNG files (`LoadPNG`).
    *   `OpenGLWindow`: A Cython class that encapsulates an SDL2 window with an OpenGL context. It handles:
        *   Window creation and management.
        *   OpenGL initialization and basic setup.
        *   Compilation and management of GLSL shader programs.
        *   Loading image data from `ImageSurface` objects into OpenGL textures.
        *   Drawing 2D textured elements (HUD elements).
        *   Basic timing functions using `SDL_Delay`.
    *   Contains `ready()` and `quit()` functions to initialize and shut down SDL.

*   **`resources.pyx`:**
    *   A Cython module for managing game resources.
    *   `ResourceArchive`: A class to load and access resources from a ZIP file (specifically `PyDoomResource.zip`).
    *   It can also load Python "game modules" listed in `Games.txt` from within the ZIP archive, allowing for different game configurations or mods.

*   **`wadfile.pyx`:**
    *   A Cython module dedicated to reading and parsing Doom WAD (Where's All the Data?) files.
    *   `is_wadfile()`: Checks if a given file is a valid WAD file.
    *   `WadEntry`: Represents a single "lump" (a data entry, like a graphic, sound, or map data) within a WAD file. It can read the lump's data on demand.
    *   `WadFile`: Represents an entire WAD file. It reads the WAD directory (index of lumps) and provides methods to find and access lumps by name. It also understands WAD namespaces (e.g., `S_START` for sprites, `F_START` for flats).

## 2. Implemented Features

This section details the features that are currently implemented in PyDoom.

### 2.1. Initialization & Configuration

*   **Logging:**
    *   A master logger (`PyDoom`) is set up in `pydoom.py`.
    *   Log output is directed to both the console (`stdout`) and a file (`pydoom.log`).
    *   Log format includes level, logger name, and message.
*   **Command-Line Argument Parsing:**
    *   The `ArgumentParser` class in `pydoom/arguments.py` handles parsing of command-line arguments.
    *   Supported arguments include:
        *   `-game <gamename>`: Specifies the game to play (though game selection logic is rudimentary).
        *   `-file <file1.wad> ...`: Specifies external resource files to load.
        *   `-fullscreen` / `-windowed`: Sets display mode.
        *   `-width <pixels>` / `-height <pixels>`: Sets window/screen dimensions.
        *   `-renderer <software|opengl>`: (Not currently used) Intended to specify the renderer.
*   **Configuration File (`pydoom.ini`):**
    *   Managed by `pydoom/configuration.py`.
    *   A default `pydoom.ini` is created if one doesn't exist in the program directory.
    *   Currently stores and loads video settings: `fullscreen`, `width`, `height`.

### 2.2. Resource Handling

*   **Main Resource Archive (`PyDoomResource.zip`):**
    *   Loaded by the `ResourceArchive` class in `pydoom/resources.pyx`.
    *   This ZIP file is expected to contain game scripts (Python modules), fonts, graphics, and shaders.
    *   `Games.txt` within the archive lists game modules to be imported, allowing for different game setups.
*   **WAD File Loading:**
    *   Handled by `WadFile` and `WadEntry` classes in `pydoom/wadfile.pyx`.
    *   Can identify and parse `IWAD` and `PWAD` formats.
    *   Lumps (data entries) within WAD files can be accessed by name (e.g., `FindFirstLump`, `FindAllLumps`).
    *   Recognizes WAD namespaces (global, sprites `S_START`/`S_END`, flats `F_START`/`F_END`) to categorize lumps, although this categorization is not heavily used yet.
    *   Lump data is read on demand.

### 2.3. Graphics & Rendering

*   **SDL2 and OpenGL ES 2 Initialization:**
    *   The `OpenGLWindow` class in `pydoom/interface.pyx` initializes SDL2 and creates an OpenGL ES 2 context.
    *   It sets up basic OpenGL attributes (color depth, multisampling).
*   **Window Management:**
    *   Supports creating a window with specified dimensions and title.
    *   Can toggle fullscreen mode (though `fullwindow` option seems to be for borderless fullscreen).
*   **Basic 2D Shader:**
    *   `pydoom.py` hardcodes a simple vertex and fragment shader for 2D rendering.
    *   The vertex shader transforms 2D coordinates to screen space.
    *   The fragment shader samples a texture and outputs its color.
    *   Shaders are compiled and linked by `OpenGLWindow.compileProgram()`.
*   **Texture Loading:**
    *   `OpenGLWindow.loadTexture()` takes an `ImageSurface` and creates an OpenGL texture.
    *   Supports RGBA8 textures with mipmapping and nearest neighbor filtering.
*   **`TITLEPIC` Display:**
    *   As a demonstration, `pydoom.py` loads the `TITLEPIC` lump from `doom2.wad` and the `PLAYPAL` (palette) lump.
    *   `ImageSurface.LoadDoomGraphic()` converts the Doom graphic and palette into an RGBA `ImageSurface`.
    *   This surface is then loaded as an OpenGL texture and drawn to fill the screen using `OpenGLWindow.drawHud()`.

### 2.4. Image Loading

*   **Doom Graphic Format (`ImageSurface.LoadDoomGraphic`):**
    *   Located in `pydoom/interface.pyx` (and a similar one in `pydoom/graphics.py`'s `Image` class).
    *   Parses the column-based Doom graphic format.
    *   Uses a provided palette (e.g., from `PLAYPAL`) to convert indexed colors to RGBA.
    *   Handles image offsets stored in the graphic.
*   **PNG Image Loading (`ImageSurface.LoadPNG`):**
    *   Located in `pydoom/interface.pyx`.
    *   Supports loading various PNG color types (Greyscale, Truecolor, Indexed, with or without Alpha).
    *   Handles PNG chunks like `IHDR`, `PLTE`, `IDAT`, `IEND`, `tRNS` (for transparency), and ZDoom's `grAb` (for offsets).
    *   Includes zlib decompression for `IDAT` chunks.
    *   Applies PNG filters (None, Subtract, Upper, Average, Paeth) to reconstruct pixel data.

## 3. Core Classes and APIs

This section provides an overview of the main classes used in PyDoom and their primary functionalities.

### 3.1. `ArgumentParser` (`pydoom/arguments.py`)

*   **Responsibility:** Parses command-line arguments provided to the game.
*   **Key Properties:**
    *   `game`: Stores the name of the game to be played (e.g., "doom2").
    *   `files`: A list of external WAD/ZIP files to load.
    *   `resolution`: A list `[width, height]` for screen dimensions.
    *   `fullscreen`: Boolean indicating if fullscreen mode is requested.
    *   `renderer`: String for the preferred renderer (currently not used).
*   **Key Methods:**
    *   `__init__(self, arglist)`: Initializes the parser with a list of arguments.
    *   `CollectArgs(self)`: Processes the argument list.
    *   `ParseOptions(self, options)`: Dispatches to specific `ParseOpt_*` methods based on the argument.
    *   `ParseOpt_game(self, game)`: Handles `-game`.
    *   `ParseOpt_file(self, *files)`: Handles `-file`.
    *   `ParseOpt_fullscreen(self)`: Handles `-fullscreen`.
    *   `ParseOpt_windowed(self)`: Handles `-windowed`.
    *   `ParseOpt_width(self, width)`: Handles `-width`.
    *   `ParseOpt_height(self, height)`: Handles `-height`.

### 3.2. `ResourceArchive` (`pydoom/resources.pyx`)

*   **Responsibility:** Manages loading resources from a main ZIP archive (typically `PyDoomResource.zip`). This archive contains game scripts and shared assets.
*   **Key Properties:**
    *   `filename`: Path to the resource ZIP file.
    *   `game_modules`: A list of imported Python modules that define games, loaded based on `Games.txt` within the archive.
*   **Key Methods:**
    *   `__init__(self, filename)`: Opens the ZIP file and reads `Games.txt` to load game modules.
    *   `readGames(self)`: Reads `Games.txt` and imports the specified Python modules from the `scripts/` directory within the ZIP.
    *   `importModule(self, modulename)`: Imports a Python module from within the ZIP archive's `scripts/` path.
    *   The class also uses `zipfile.ZipFile` internally to access other files within the archive, though direct methods for general file access are not explicitly exposed beyond game module loading.

### 3.3. `WadFile` (`pydoom/wadfile.pyx`)

*   **Responsibility:** Reads and provides access to the content of WAD files.
*   **Key Properties:**
    *   `entries`: A list of `WadEntry` objects representing all lumps in the WAD file.
*   **Key Methods:**
    *   `__init__(self, filename)`: Opens the WAD file, reads its header and directory (list of lumps).
    *   `FindFirstLump(self, name)`: Returns the first `WadEntry` that matches the given lump name (case-insensitive).
    *   `FindAllLumps(self, name)`: Returns a list of all `WadEntry` objects that match the given lump name.
    *   `is_wadfile(filename)` (module-level function): Checks if a file is a valid WAD file by inspecting its magic number.

### 3.4. `WadEntry` (`pydoom/wadfile.pyx`)

*   **Responsibility:** Represents a single lump (data entry) within a WAD file.
*   **Key Properties:**
    *   `name`: The 8-character name of the lump (as bytes).
    *   `size`: The size of the lump data in bytes.
    *   `namespace`: An integer indicating the namespace the lump belongs to (e.g., `NS_GLOBAL`, `NS_SPRITES`, `NS_FLATS`). Determined by marker lumps like `S_START`.
    *   `index`: The lump's index in the WAD directory.
*   **Key Methods:**
    *   `read(self)`: Reads the lump's data from the WAD file (if not already read) and returns it as a byte string. Data is cached after the first read.

### 3.5. `ImageSurface` (`pydoom/interface.pyx`)

*   **Responsibility:** A Cython class that holds raw pixel data (RGBA) and provides methods to load images from various formats into this raw representation. This is the primary format for texture data before uploading to OpenGL.
*   **Key Properties:**
    *   `width`: Width of the image in pixels.
    *   `height`: Height of the image in pixels.
    *   `xoffset`, `yoffset`: Horizontal and vertical offsets for the image (often used for Doom sprites).
    *   `data`: A pointer to the raw buffer of unsigned char RGBA pixel data.
*   **Key Methods:**
    *   `__init__(self, width, height)`: Creates a new blank `ImageSurface`.
    *   `getPixel(self, x, y)`: Returns the (R, G, B, A) tuple for a given coordinate.
    *   `setPixel(self, x, y, color)`: Sets the pixel at a given coordinate.
    *   `getPixelDirect(self, x, y)` (cdef): Directly gets a packed integer color.
    *   `setPixelDirect(self, x, y, color)` (cdef): Directly sets a packed integer color.
    *   `LoadDoomGraphic(cls, bytebuffer, palette_bytes)` (classmethod): Loads a Doom patch/graphic from its raw byte data and a raw palette byte string, converting it into an RGBA `ImageSurface`.
    *   `LoadPNG(cls, bytebuffer)` (classmethod): Loads a PNG image from its raw byte data into an RGBA `ImageSurface`. Handles various PNG color types, transparency, and filters.

### 3.6. `OpenGLWindow` (`pydoom/interface.pyx`)

*   **Responsibility:** Manages the SDL window, OpenGL context, shader programs, and texture rendering.
*   **Key Methods:**
    *   `__init__(self, title, width, height, fullscreen, fullwindow, display, x, y)`: Creates an SDL window with an OpenGL ES 2 context.
    *   `clear(self)`: Clears the color, depth, and stencil buffers.
    *   `swap(self)`: Swaps the front and back buffers to display the rendered frame.
    *   `compileProgram(self, name, fragShader_source, vertShader_source)`: Compiles GLSL vertex and fragment shaders and links them into a named program.
    *   `unloadProgram(self, name)`: Deletes a compiled shader program.
    *   `useProgram2D(self, name)` / `useProgram3D(self, name)`: Sets the active shader program for 2D/3D drawing (currently only 2D is practically used).
    *   `loadTexture(self, name, ImageSurface image)`: Uploads pixel data from an `ImageSurface` to an OpenGL texture, associating it with a name.
    *   `unloadTexture(self, name)`: Deletes an OpenGL texture.
    *   `drawHud(self, texture_name, left, top, width, height)`: Draws a named texture as a 2D HUD element. Coordinates and dimensions are normalized (0.0 to 1.0 relative to screen size).
    *   `tick(self, delay_ms)`: Pauses execution for a specified duration using `SDL_Delay` and returns the actual time elapsed.
*   **Module-level functions in `interface.pyx`:**
    *   `ready()`: Initializes SDL subsystems (Timer, Video, Events). Must be called before creating an `OpenGLWindow`.
    *   `quit()`: Shuts down SDL.

### 3.7. `Palette` (`pydoom/graphics.py`)

*   **Responsibility:** Represents a 256-color palette.
*   **Key Properties:**
    *   `colors`: A list of `PaletteIndex` objects.
*   **Key Methods:**
    *   `MakePalettes(byteseq)` (module-level function): Parses a binary PLAYPAL lump (which can contain multiple palettes) and returns a list of `Palette` objects.

### 3.8. `PaletteIndex` (`pydoom/graphics.py`)

*   **Responsibility:** Represents a single color entry (Red, Green, Blue) within a `Palette`.
*   **Key Properties:**
    *   `red`, `green`, `blue`: Integer color components (0-255).

### 3.9. `Image` (`pydoom/graphics.py`)

*   **Responsibility:** An older/alternative Python-level class for representing an image with an RGBA buffer. `ImageSurface` in `interface.pyx` is generally preferred for direct OpenGL interaction.
*   **Key Properties:**
    *   `width`, `height`: Dimensions of the image.
    *   `xoffset`, `yoffset`: Image offsets.
    *   `data`: An `ImageSurface` object (from `pydoom.video`, which seems to be an earlier name or version of `pydoom.interface.ImageSurface` or a direct binding).
*   **Key Methods:**
    *   `__init__(self, width, height, xofs, yofs)`: Creates a new `Image`.
    *   `GetPixel(self, x, y)` / `SetPixel(self, x, y, color)`: Pixel access methods.
    *   `LoadDoomGraphic(cls, bytebuffer, palette)` (classmethod): Loads a Doom graphic using a `Palette` object.
    *   `LoadPNG(cls, bytebuffer)` (classmethod): A partially implemented PNG loader. The one in `interface.pyx.ImageSurface` is more complete.

## 4. To-Be-Implemented Features / Roadmap

This section outlines major features and systems that are needed to develop PyDoom into a more complete and functional game. The current codebase provides a foundation for graphics and resource loading, but core gameplay elements are largely missing.

### 4.1. Core Game Loop & State Management

*   **Main Game Loop:** Implement a robust game loop in `pydoom.py` or `core.pyx` that handles timing, updates, and rendering consistently.
*   **Event Handling:**
    *   Process SDL events (keyboard, mouse, window events).
    *   Map raw input to game actions (e.g., player movement, shooting, UI interaction).
*   **Game State Machine:**
    *   Implement a system to manage different game states (e.g., Main Menu, In-Game, Paused, Options Screen).
    *   Each state would have its own logic for updates, rendering, and event handling.

### 4.2. Gameplay Mechanics (`pydoom/core.pyx`)

*   **Player Entity:**
    *   Position, orientation, movement physics (including collision).
    *   Health, armor, inventory (weapons, ammo, keys, power-ups).
    *   Weapon switching and firing mechanics.
*   **Map/Level Processing:**
    *   Load and parse detailed map data from WAD files (linedefs, sidedefs, vertices, sectors, things).
    *   Construct a usable 2D/3D representation of the level for rendering and gameplay.
*   **Collision Detection:**
    *   Player-wall collisions.
    *   Player-object collisions.
    *   Projectile-actor/wall collisions.
*   **Things (Entities):**
    *   Generic system for managing game objects (enemies, items, decorations, projectiles).
    *   Spawning and tracking entities based on map data.
*   **Enemy AI:**
    *   Basic enemy behaviors (e.g., sight, sound detection, movement, attacking).
    *   Pathfinding (simple or complex).
*   **Projectile System:**
    *   Spawning projectiles (bullets, rockets).
    *   Movement and collision.
*   **Sector Effects:**
    *   Doors, lifts, crushers, secret areas.
    *   Changes in floor/ceiling height, lighting.
*   **Game Rules & Progression:**
    *   Level exit conditions.
    *   Transitioning between levels.
    *   Saving/loading game state (optional, advanced).

### 4.3. Rendering Engine (`pydoom/interface.pyx` & Shaders)

*   **3D Rendering Pipeline:**
    *   Develop a proper 3D rendering pipeline. The current shader is only for fullscreen 2D.
    *   Perspective projection, view transformations.
*   **Map Rendering:**
    *   Render walls (linedefs/sidedefs).
    *   Render floors and ceilings (flats/sectors).
    *   Texture mapping with correct perspective and lighting.
    *   Handling of visplanes/visportals for optimization (classic Doom technique).
*   **Sprite Rendering:**
    *   Render game entities (enemies, items) as sprites ("billboards") in the 3D world.
    *   Handle sprite orientation, scaling, and translucency.
*   **Weapon View Model:**
    *   Render the player's weapon from a first-person perspective.
*   **Lighting:**
    *   Implement sector-based lighting from WAD data.
    *   Dynamic lighting effects (muzzle flashes, explosions) would be an advanced addition.
*   **Skybox/Sky Texture:**
    *   Render sky textures.

### 4.4. User Interface (UI)

*   **Main Menu:**
    *   Options: New Game, Load Game (if implemented), Options, Quit.
    *   Navigation and selection.
*   **In-Game HUD:**
    *   Display player health, armor, ammo, keys, current weapon.
    *   Render the status bar (classic Doom-style or custom).
*   **Options/Settings Menu:**
    *   Allow configuration of video, audio, controls.
*   **Console:**
    *   A command console for debugging or cheats (common in Doom-likes).
    *   The existing `ConsoleBackground.png` suggests this might be planned.
*   **Font Rendering:**
    *   Load and render text using bitmap fonts (e.g., `PyFont.png`).

### 4.5. Audio System (using BASS library)

*   **Integration of BASS:** The BASS library is in `extern/`, but not used.
    *   Initialize BASS.
    *   Load sound formats (e.g., Doom's DMX, WAV, OGG).
*   **Sound Effect Playback:**
    *   Trigger sound effects for weapon fire, impacts, enemy actions, item pickups, UI interactions.
    *   Positional audio (3D sound) would be an advanced feature.
*   **Music Playback:**
    *   Load and play level music from WAD files or external sources.
    *   Looping and transitions.

### 4.6. Asset Pipeline & Management

*   **Comprehensive WAD Parsing:**
    *   Ensure all necessary lump types for gameplay are parsed correctly (MAPxx, TEXTUREx, PNAMES, etc.).
*   **Texture Management:**
    *   Handle TEXTUREx and PNAMES lumps to compose wall textures from patches.
    *   Manage flats (floor/ceiling textures).
*   **Sprite Management:**
    *   Group sprite frames for animations.
*   **Sound Lump Parsing:**
    *   Extract sound data from WAD files.

### 4.7. Scripting & Modding Enhancements

*   **Refine Game Module System:**
    *   The `ResourceArchive` can load game modules. Define a clearer API or structure for how these modules interact with the core engine to define game behavior, entities, or rules.

### 4.8. Build and Distribution

*   **Refine Build Process:**
    *   Ensure `setup_exe.py` (for cx_Freeze) and `setup_extensions.py` (for Cython modules) are robust.
    *   `MakeZip.py` should reliably package all necessary resources into `PyDoomResource.zip`.
