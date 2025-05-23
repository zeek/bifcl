cmake_minimum_required(VERSION 3.15.0 FATAL_ERROR)
project(BifCl C CXX)

include(cmake/CommonCMakeConfig.cmake)

find_package(BISON REQUIRED)
find_package(FLEX REQUIRED)

if (MSVC)
    add_compile_options(/J) # Similar to -funsigned-char on other platforms
    set_property(SOURCE bif_lex.cc APPEND_STRING PROPERTY COMPILE_FLAGS "/wd4018")
else ()
    set_property(SOURCE bif_lex.cc APPEND_STRING PROPERTY COMPILE_FLAGS "-Wno-sign-compare")
endif ()

include_directories(BEFORE ${BifCl_SOURCE_DIR}/include ${BifCl_BINARY_DIR})

set(BISON_FLAGS "--debug")

# BIF parser/scanner
bison_target(BIFParser builtin-func.y ${BifCl_BINARY_DIR}/bif_parse.cc
             DEFINES_FILE ${BifCl_BINARY_DIR}/bif_parse.h COMPILE_FLAGS "${BISON_FLAGS}")
flex_target(BIFScanner builtin-func.l ${BifCl_BINARY_DIR}/bif_lex.cc)
add_flex_bison_dependency(BIFScanner BIFParser)

set(bifcl_SRCS
    ${BISON_BIFParser_INPUT}
    ${FLEX_BIFScanner_INPUT}
    ${BISON_BIFParser_OUTPUTS}
    ${FLEX_BIFScanner_OUTPUTS}
    bif_arg.cc
    include/bif_arg.h
    module_util.cc
    include/module_util.h)

add_executable(bifcl ${bifcl_SRCS})
target_compile_features(bifcl PRIVATE cxx_std_17)
set_target_properties(bifcl PROPERTIES CXX_EXTENSIONS OFF)

if (MSVC)
    # If building separately from zeek, we need to add the libunistd subdirectory
    # so that linking doesn't fail.
    if ("${CMAKE_PROJECT_NAME}" STREQUAL "BifCl")
        add_subdirectory(auxil/libunistd EXCLUDE_FROM_ALL)
    endif ()
    target_link_libraries(bifcl PRIVATE libunistd)
endif ()

install(TARGETS bifcl DESTINATION bin)

if (CMAKE_BUILD_TYPE)
    string(TOUPPER ${CMAKE_BUILD_TYPE} BuildType)
endif ()

message(
    "\n====================|  Bifcl Build Summary  |====================="
    "\n"
    "\nBuild type:        ${CMAKE_BUILD_TYPE}"
    "\nBuild dir:         ${PROJECT_BINARY_DIR}"
    "\nInstall prefix:    ${CMAKE_INSTALL_PREFIX}"
    "\nDebug mode:        ${ENABLE_DEBUG}"
    "\n"
    "\nCC:                ${CMAKE_C_COMPILER}"
    "\nCFLAGS:            ${CMAKE_C_FLAGS} ${CMAKE_C_FLAGS_${BuildType}}"
    "\nCXX:               ${CMAKE_CXX_COMPILER}"
    "\nCXXFLAGS:          ${CMAKE_CXX_FLAGS} ${CMAKE_CXX_FLAGS_${BuildType}}"
    "\nCPP:               ${CMAKE_CXX_COMPILER}"
    "\n"
    "\n================================================================\n")

include(UserChangedWarning)
