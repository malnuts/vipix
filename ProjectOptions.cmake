include(cmake/SystemLink.cmake)
include(cmake/LibFuzzer.cmake)
include(CMakeDependentOption)
include(CheckCXXCompilerFlag)


macro(vipix_supports_sanitizers)
  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND NOT WIN32)
    set(SUPPORTS_UBSAN ON)
  else()
    set(SUPPORTS_UBSAN OFF)
  endif()

  if((CMAKE_CXX_COMPILER_ID MATCHES ".*Clang.*" OR CMAKE_CXX_COMPILER_ID MATCHES ".*GNU.*") AND WIN32)
    set(SUPPORTS_ASAN OFF)
  else()
    set(SUPPORTS_ASAN ON)
  endif()
endmacro()

macro(vipix_setup_options)
  option(vipix_ENABLE_HARDENING "Enable hardening" ON)
  option(vipix_ENABLE_COVERAGE "Enable coverage reporting" OFF)
  cmake_dependent_option(
    vipix_ENABLE_GLOBAL_HARDENING
    "Attempt to push hardening options to built dependencies"
    ON
    vipix_ENABLE_HARDENING
    OFF)

  vipix_supports_sanitizers()

  if(NOT PROJECT_IS_TOP_LEVEL OR vipix_PACKAGING_MAINTAINER_MODE)
    option(vipix_ENABLE_IPO "Enable IPO/LTO" OFF)
    option(vipix_WARNINGS_AS_ERRORS "Treat Warnings As Errors" OFF)
    option(vipix_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(vipix_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" OFF)
    option(vipix_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(vipix_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" OFF)
    option(vipix_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(vipix_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(vipix_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(vipix_ENABLE_CLANG_TIDY "Enable clang-tidy" OFF)
    option(vipix_ENABLE_CPPCHECK "Enable cpp-check analysis" OFF)
    option(vipix_ENABLE_PCH "Enable precompiled headers" OFF)
    option(vipix_ENABLE_CACHE "Enable ccache" OFF)
  else()
    option(vipix_ENABLE_IPO "Enable IPO/LTO" ON)
    option(vipix_WARNINGS_AS_ERRORS "Treat Warnings As Errors" ON)
    option(vipix_ENABLE_USER_LINKER "Enable user-selected linker" OFF)
    option(vipix_ENABLE_SANITIZER_ADDRESS "Enable address sanitizer" ${SUPPORTS_ASAN})
    option(vipix_ENABLE_SANITIZER_LEAK "Enable leak sanitizer" OFF)
    option(vipix_ENABLE_SANITIZER_UNDEFINED "Enable undefined sanitizer" ${SUPPORTS_UBSAN})
    option(vipix_ENABLE_SANITIZER_THREAD "Enable thread sanitizer" OFF)
    option(vipix_ENABLE_SANITIZER_MEMORY "Enable memory sanitizer" OFF)
    option(vipix_ENABLE_UNITY_BUILD "Enable unity builds" OFF)
    option(vipix_ENABLE_CLANG_TIDY "Enable clang-tidy" ON)
    option(vipix_ENABLE_CPPCHECK "Enable cpp-check analysis" ON)
    option(vipix_ENABLE_PCH "Enable precompiled headers" OFF)
    option(vipix_ENABLE_CACHE "Enable ccache" ON)
  endif()

  if(NOT PROJECT_IS_TOP_LEVEL)
    mark_as_advanced(
      vipix_ENABLE_IPO
      vipix_WARNINGS_AS_ERRORS
      vipix_ENABLE_USER_LINKER
      vipix_ENABLE_SANITIZER_ADDRESS
      vipix_ENABLE_SANITIZER_LEAK
      vipix_ENABLE_SANITIZER_UNDEFINED
      vipix_ENABLE_SANITIZER_THREAD
      vipix_ENABLE_SANITIZER_MEMORY
      vipix_ENABLE_UNITY_BUILD
      vipix_ENABLE_CLANG_TIDY
      vipix_ENABLE_CPPCHECK
      vipix_ENABLE_COVERAGE
      vipix_ENABLE_PCH
      vipix_ENABLE_CACHE)
  endif()

  vipix_check_libfuzzer_support(LIBFUZZER_SUPPORTED)
  if(LIBFUZZER_SUPPORTED AND (vipix_ENABLE_SANITIZER_ADDRESS OR vipix_ENABLE_SANITIZER_THREAD OR vipix_ENABLE_SANITIZER_UNDEFINED))
    set(DEFAULT_FUZZER ON)
  else()
    set(DEFAULT_FUZZER OFF)
  endif()

  option(vipix_BUILD_FUZZ_TESTS "Enable fuzz testing executable" ${DEFAULT_FUZZER})

endmacro()

macro(vipix_global_options)
  if(vipix_ENABLE_IPO)
    include(cmake/InterproceduralOptimization.cmake)
    vipix_enable_ipo()
  endif()

  vipix_supports_sanitizers()

  if(vipix_ENABLE_HARDENING AND vipix_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR vipix_ENABLE_SANITIZER_UNDEFINED
       OR vipix_ENABLE_SANITIZER_ADDRESS
       OR vipix_ENABLE_SANITIZER_THREAD
       OR vipix_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    message("${vipix_ENABLE_HARDENING} ${ENABLE_UBSAN_MINIMAL_RUNTIME} ${vipix_ENABLE_SANITIZER_UNDEFINED}")
    vipix_enable_hardening(vipix_options ON ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()
endmacro()

macro(vipix_local_options)
  if(PROJECT_IS_TOP_LEVEL)
    include(cmake/StandardProjectSettings.cmake)
  endif()

  add_library(vipix_warnings INTERFACE)
  add_library(vipix_options INTERFACE)

  include(cmake/CompilerWarnings.cmake)
  vipix_set_project_warnings(
    vipix_warnings
    ${vipix_WARNINGS_AS_ERRORS}
    ""
    ""
    ""
    "")

  if(vipix_ENABLE_USER_LINKER)
    include(cmake/Linker.cmake)
    vipix_configure_linker(vipix_options)
  endif()

  include(cmake/Sanitizers.cmake)
  vipix_enable_sanitizers(
    vipix_options
    ${vipix_ENABLE_SANITIZER_ADDRESS}
    ${vipix_ENABLE_SANITIZER_LEAK}
    ${vipix_ENABLE_SANITIZER_UNDEFINED}
    ${vipix_ENABLE_SANITIZER_THREAD}
    ${vipix_ENABLE_SANITIZER_MEMORY})

  set_target_properties(vipix_options PROPERTIES UNITY_BUILD ${vipix_ENABLE_UNITY_BUILD})

  if(vipix_ENABLE_PCH)
    target_precompile_headers(
      vipix_options
      INTERFACE
      <vector>
      <string>
      <utility>)
  endif()

  if(vipix_ENABLE_CACHE)
    include(cmake/Cache.cmake)
    vipix_enable_cache()
  endif()

  include(cmake/StaticAnalyzers.cmake)
  if(vipix_ENABLE_CLANG_TIDY)
    vipix_enable_clang_tidy(vipix_options ${vipix_WARNINGS_AS_ERRORS})
  endif()

  if(vipix_ENABLE_CPPCHECK)
    vipix_enable_cppcheck(${vipix_WARNINGS_AS_ERRORS} "" # override cppcheck options
    )
  endif()

  if(vipix_ENABLE_COVERAGE)
    include(cmake/Tests.cmake)
    vipix_enable_coverage(vipix_options)
  endif()

  if(vipix_WARNINGS_AS_ERRORS)
    check_cxx_compiler_flag("-Wl,--fatal-warnings" LINKER_FATAL_WARNINGS)
    if(LINKER_FATAL_WARNINGS)
      # This is not working consistently, so disabling for now
      # target_link_options(vipix_options INTERFACE -Wl,--fatal-warnings)
    endif()
  endif()

  if(vipix_ENABLE_HARDENING AND NOT vipix_ENABLE_GLOBAL_HARDENING)
    include(cmake/Hardening.cmake)
    if(NOT SUPPORTS_UBSAN 
       OR vipix_ENABLE_SANITIZER_UNDEFINED
       OR vipix_ENABLE_SANITIZER_ADDRESS
       OR vipix_ENABLE_SANITIZER_THREAD
       OR vipix_ENABLE_SANITIZER_LEAK)
      set(ENABLE_UBSAN_MINIMAL_RUNTIME FALSE)
    else()
      set(ENABLE_UBSAN_MINIMAL_RUNTIME TRUE)
    endif()
    vipix_enable_hardening(vipix_options OFF ${ENABLE_UBSAN_MINIMAL_RUNTIME})
  endif()

endmacro()
