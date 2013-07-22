
LIB_NAME = ptllvm
FILES =  llvmUtils llvmBitcode llvmPPrint llvmDecode llvmEval
TEST_FILES = testLlvmDecode
ONLY_MLI_FILES = llvmAst
INCLUDE_DIR = ../utools/ ../extlib/ /usr/local/llvm32/lib/ocaml
DEP_LIBS = utools.cmxa llvm.cmxa llvm_executionengine.cmxa llvm_bitreader.cmxa extlib.cmxa
UNITTEST_DIR = utest
