cmake_minimum_required (VERSION 2.8)
project (perl-bridge)

execute_process (COMMAND perl -MConfig -e "print \$Config{ccflags}" OUTPUT_VARIABLE PERL_C_FLAGS)
set (CMAKE_C_FLAGS ${PERL_C_FLAGS})

set (CMAKE_BUILD_TYPE Debug)

set (SOURCE_FILES
        src/perlxsi.c
        src/perl_bridge.c)

include_directories (include)

link_libraries (perl)

execute_process (COMMAND perl -MConfig -e "print \$Config{archlib}" OUTPUT_VARIABLE PERL_LIB)
include_directories (${PERL_LIB}/CORE)

add_library (${PROJECT_NAME} STATIC ${SOURCE_FILES})
