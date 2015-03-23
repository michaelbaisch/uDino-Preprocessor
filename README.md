# µDino Preprocessor

This is the preprocessor used in the Mac Application [µDino](http://udino.de). It is used to process the files of an Arduino project before compilation. The code is inspired from [here](https://github.com/ffissore/Arduino/blob/coanctags/arduino-core/src/processing/app/preproc/CTagsParser.java).

Users of the [Arduino-Makefile](https://github.com/sudar/Arduino-Makefile) could use this preprocessor to create prototypes and work with multiple .ino / .pde files.

To create the prototypes a [patched version](https://github.com/ffissore/ctags) of ctags used.

<br />
### Usage:

	./preprocessor.rb project_folder output_folder

__Keep in mind that all Arduino and C source files in _output_folder_ will be deleted!__



