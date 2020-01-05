@echo off
setlocal

call "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvarsall.bat" x86

cl /I. /LD /Gz /O2 rail_wrapper.cpp /link /def:rail_wrapper.def
del *.exp *.lib *.obj
pedump --pe rail_wrapper.dll | rg Machine
pedump -E rail_wrapper.dll
