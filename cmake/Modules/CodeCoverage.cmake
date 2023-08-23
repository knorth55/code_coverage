# Copyright (c) 2012 - 2017, Lars Bilke
# All rights reserved.
# From: https://github.com/bilke/cmake-modules/blob/master/CodeCoverage.cmake
#
# Redistribution and use in source and binary forms, with or without modification,
# are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software without
#    specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
# ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
#
# CHANGES:
#
# 2012-01-31, Lars Bilke
# - Enable Code Coverage
#
# 2013-09-17, Joakim Söderberg
# - Added support for Clang.
# - Some additional usage instructions.
#
# 2016-02-03, Lars Bilke
# - Refactored functions to use named parameters
#
# 2017-06-02, Lars Bilke
# - Merged with modified version from github.com/ufz/ogs
#
# 2018-06-12, Michael Ferguson
# - Forked for ROS support
#
# 2020-10-28, Stefan Fabian
# - Added python3-coverage support
#

include(CMakeParseArguments)

# Check prereqs
find_program(GCOV_PATH gcov)
find_program(LCOV_PATH NAMES lcov lcov.bat lcov.exe lcov.perl)
find_program(GCOVR_PATH gcovr PATHS ${CMAKE_SOURCE_DIR}/scripts/test)
find_program(SIMPLE_PYTHON_EXECUTABLE python)
find_program(PYTHON_COVERAGE_PATH python-coverage)

if(NOT PYTHON_COVERAGE_PATH)
  find_program(PYTHON_COVERAGE_PATH python3-coverage)
endif()

if(NOT GCOV_PATH)
  message(FATAL_ERROR "gcov not found! Aborting...")
endif() # NOT GCOV_PATH

if(NOT PYTHON_COVERAGE_PATH)
  message(FATAL_ERROR "Neither python3-coverage nor python-coverage not found! Aborting...")
endif()

if("${CMAKE_CXX_COMPILER_ID}" MATCHES "(Apple)?[Cc]lang")
  if("${CMAKE_CXX_COMPILER_VERSION}" VERSION_LESS 3)
    message(FATAL_ERROR "Clang version must be 3.0.0 or greater! Aborting...")
  endif()
elseif(NOT CMAKE_COMPILER_IS_GNUCXX)
  message(FATAL_ERROR "Compiler is not GNU gcc! Aborting...")
endif()

set(COVERAGE_COMPILER_FLAGS "-g -O0 --coverage -fprofile-arcs -ftest-coverage"
    CACHE INTERNAL "")

set(CMAKE_CXX_FLAGS_COVERAGE ${COVERAGE_COMPILER_FLAGS}
    CACHE STRING "Flags used by the C++ compiler during coverage builds."
    FORCE)
set(CMAKE_C_FLAGS_COVERAGE ${COVERAGE_COMPILER_FLAGS}
    CACHE STRING "Flags used by the C compiler during coverage builds."
    FORCE)
set(CMAKE_EXE_LINKER_FLAGS_COVERAGE ""
    CACHE STRING "Flags used for linking binaries during coverage builds."
    FORCE)
set(CMAKE_SHARED_LINKER_FLAGS_COVERAGE ""
    CACHE STRING "Flags used by the shared libraries linker during coverage builds."
    FORCE)
mark_as_advanced(
  CMAKE_CXX_FLAGS_COVERAGE
  CMAKE_C_FLAGS_COVERAGE
  CMAKE_EXE_LINKER_FLAGS_COVERAGE
  CMAKE_SHARED_LINKER_FLAGS_COVERAGE)

if(NOT CMAKE_BUILD_TYPE STREQUAL "Debug")
  message(WARNING "Code coverage results with an optimised (non-Debug) build may be misleading")
endif() # NOT CMAKE_BUILD_TYPE STREQUAL "Debug"

if(CMAKE_C_COMPILER_ID STREQUAL "GNU")
  link_libraries(gcov)
else()
  set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} --coverage")
endif()

# Defines a target for running and collection code coverage information
# Builds dependencies, runs all the ROS tests and outputs reports.
# NOTE! The executable should always have a ZERO as exit code otherwise
# the coverage generation will not complete.
#
# ADD_CODE_COVERAGE(
#     NAME testrunner_coverage                    # New target name
# )
function(ADD_CODE_COVERAGE)

  set(options NONE)
  set(oneValueArgs NAME)
  set(multiValueArgs EXCLUDES;INCLUDE_PYTHON_DIRECTORIES)
  cmake_parse_arguments(Coverage "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT LCOV_PATH)
    message(FATAL_ERROR "lcov not found! Aborting...")
  endif() # NOT LCOV_PATH

  # Determine directory to store python coverage files
  set(COVERAGE_DIR $ENV{HOME}/.ros)
  if(DEFINED ENV{ROS_HOME})
    set(COVERAGE_DIR $ENV{ROS_HOME})
  endif()

  # Ensure that the include component uses the correct path for symlinked source directories
  get_filename_component(REAL_SOURCE_DIR ${PROJECT_SOURCE_DIR} REALPATH)

  # python omit and include flags
  list(APPEND Coverage_EXCLUDES "${REAL_SOURCE_DIR}/test/*" "${REAL_SOURCE_DIR}/tests/*")
  string(REPLACE ";" "," Coverage_EXCLUDES_STR "${Coverage_EXCLUDES}")
  set(OMIT_FLAGS "--omit=\"${Coverage_EXCLUDES_STR}\"")
  set(INCLUDE_FLAGS "--include=\"${REAL_SOURCE_DIR}/*\"")

  # cpp lcov remove flags
  set(LCOV_REMOVES ${Coverage_EXCLUDES})
  list(APPEND LCOV_REMOVES "'*${REAL_SOURCE_DIR}/test/*'" "'*${REAL_SOURCE_DIR}/tests/*'")

  # Cleanup C++ counters
  add_custom_target(${Coverage_NAME}_cleanup_cpp
    # Cleanup lcov
    COMMAND ${LCOV_PATH} --directory . --zerocounters
    # Create baseline to make sure untouched files show up in the report
    WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
    COMMENT "Resetting CPP code coverage counters to zero."
  )

  # Cleanup python counters
  add_custom_target(${Coverage_NAME}_cleanup_py
    COMMAND ${PYTHON_COVERAGE_PATH} erase
    WORKING_DIRECTORY ${COVERAGE_DIR}
    COMMENT "Resetting PYTHON code coverage counters to zero."
  )

  # add target for non-test repo
  # we need to set _run_tests_${PROJECT_NAME} for repo with no-te, otherwise test fails.
  # catkin tools executes _run_tests_${PROJECT_NAME}.
  # _run_tests_${PROJECT_NAME} is for cleaning test result and run tests.
  # https://github.com/ros/catkin/commit/f931db5c8c14475a9d74ffc65b9dbbe45c98d11d
  if(NOT TARGET _run_tests_${PROJECT_NAME})
    # create hidden meta target which depends on hidden test targets
    # which depend on clean_test_results
    add_custom_target(_run_tests_${PROJECT_NAME})
    # run_tests depends on this hidden target hierarchy
    # to clear test results before running all tests
    add_dependencies(run_tests _run_tests_${PROJECT_NAME})
  endif()

  if(NOT DEFINED CATKIN_ENABLE_TESTING OR CATKIN_ENABLE_TESTING)
    # create python base coverage directory
    add_custom_target(
      create_python_base_coverage_dir
      "${CMAKE_COMMAND}" "-E" "make_directory"
      ${PROJECT_BINARY_DIR}/python_base_coverage
    )

    # find code_coverage path
    if(code_coverage_SOURCE_DIR)
      set(_code_coverage_SOURCE_DIR ${code_coverage_SOURCE_DIR})
    elseif(code_coverage_SOURCE_PREFIX)
      set(_code_coverage_SOURCE_DIR ${code_coverage_SOURCE_PREFIX})
    else()
      set(_code_coverage_SOURCE_DIR ${code_coverage_PREFIX}/share/code_coverage)
    endif()

    # list up python source directory candidates
    set(PROJECT_PYTHON_SOURCE_DIR_CANDIDATES bin ci_scripts node_scripts scripts src)
    if(NOT "${Coverage_INCLUDE_PYTHON_DIRECTORIES}" STREQUAL "")
      list(APPEND PROJECT_PYTHON_SOURCE_DIR_CANDIDATES ${Coverage_INCLUDE_PYTHON_DIRECTORIES})
    endif()

    # check and create python source directories lists
    set(PROJECT_PYTHON_SOURCE_DIRS "")
    set(PROJECT_PYTHON_SOURCE_DIRS_RELATIVE "")
    foreach(PROJECT_PYTHON_SOURCE_DIR_CANDIDATE ${PROJECT_PYTHON_SOURCE_DIR_CANDIDATES})
      if(EXISTS ${PROJECT_SOURCE_DIR}/${PROJECT_PYTHON_SOURCE_DIR_CANDIDATE})
        list(APPEND PROJECT_PYTHON_SOURCE_DIRS
                    ${PROJECT_SOURCE_DIR}/${PROJECT_PYTHON_SOURCE_DIR_CANDIDATE})
        list(APPEND PROJECT_PYTHON_SOURCE_DIRS_RELATIVE
                    ${PROJECT_PYTHON_SOURCE_DIR_CANDIDATE})
      endif()
    endforeach()

    # set include python flags
    set(INCLUDE_PYTHON_FLAGS "")
    if(NOT "${PROJECT_PYTHON_SOURCE_DIRS_RELATIVE}" STREQUAL "")
      list(APPEND INCLUDE_PYTHON_FLAGS "--include-python-directories")
      list(APPEND INCLUDE_PYTHON_FLAGS ${PROJECT_PYTHON_SOURCE_DIRS_RELATIVE})
    endif()

    # create depends list
    set(PYTHON_BASE_COVERAGE_REPORT_DEPENDS
      create_python_base_coverage_dir
      ${_code_coverage_SOURCE_DIR}/scripts/generate_base_coverage.py
    )
    list(APPEND PYTHON_BASE_COVERAGE_REPORT_DEPENDS ${PROJECT_PYTHON_SOURCE_DIRS})

    # create python base coverage report
    # generate_base_coverage.py list up python files in the repo and generate base coverage report
    # base coverage report is needed to cover all python files, including non-tested files.
    add_custom_command(
      OUTPUT ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_python.xml
      COMMAND
        ${_code_coverage_SOURCE_DIR}/scripts/generate_base_coverage.py ${PROJECT_SOURCE_DIR}
        --output ${PROJECT_BINARY_DIR}/python_base_coverage ${INCLUDE_PYTHON_FLAGS}
      COMMAND
        ${PYTHON_COVERAGE_PATH} xml -o ${Coverage_NAME}_base_python.xml
        ${INCLUDE_FLAGS} ${OMIT_FLAGS}
        || echo "WARNING: No base python xml to output"
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${PROJECT_BINARY_DIR}/python_base_coverage/${Coverage_NAME}_base_python.xml
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_python.xml
        || echo "WARNING: No base python xml to copy"
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/python_base_coverage
      COMMENT "Generating base python coverage report."
      DEPENDS
        ${PYTHON_BASE_COVERAGE_REPORT_DEPENDS}
        ${Coverage_NAME}_cleanup_py
    )
    # hidden test target which depends on building all tests and cleaning test results
    add_custom_target(
      _run_tests_${PROJECT_NAME}_python_base_coverage_report
      DEPENDS
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_python.xml
    )

    # create cpp base coverage report
    # lcov -c -i -d in ${PROJECT_BINARY_DIR} list up cpp and header files built with coverage flags
    # and generate base coverage report
    # base coverage report is need to cover all cpp and header files, including non-tested files.
    add_custom_command(
      OUTPUT ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info
      # Create baseline to make sure untouched files show up in the report
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS}
        --initial --directory . --capture
        --output-file ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info.total
        || echo "WARNING: No base cpp report to output"
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS}
        --remove ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info.total ${LCOV_REMOVES}
        --output-file ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info.removed
        ||  echo "WARNING: No base cpp report to output"
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS}
        --extract ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info.removed
        "'*${REAL_SOURCE_DIR}*'"
        --output-file ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info.cleaned
        || echo "WARNING: No base cpp report to output"
      COMMAND
        ${CMAKE_COMMAND} -E make_directory
        ${PROJECT_BINARY_DIR}/cpp_base_coverage
        || echo "WARNING: Error to create base cpp coverage dir"
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info.cleaned
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info
        || echo "WARNING: No base cpp report to copy"
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info
        ${PROJECT_BINARY_DIR}/cpp_base_coverage/${Coverage_NAME}_base_cpp.info
        || echo "WARNING: No base cpp report to copy"
      COMMAND
        ${CMAKE_COMMAND} -E rename
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info.total
        ${PROJECT_BINARY_DIR}/cpp_base_coverage/${Coverage_NAME}_base_cpp.info.total
        || echo "WARNING: No base cpp report to move"
      COMMAND
        ${CMAKE_COMMAND} -E rename
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info.removed
        ${PROJECT_BINARY_DIR}/cpp_base_coverage/${Coverage_NAME}_base_cpp.info.removed
        || echo "WARNING: No base cpp report to move"
      COMMAND
        ${CMAKE_COMMAND} -E rename
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info.cleaned
        ${PROJECT_BINARY_DIR}/cpp_base_coverage/${Coverage_NAME}_base_cpp.info.cleaned
        || echo "WARNING: No base cpp report to move"
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
      COMMENT "Generating base cpp coverage report."
      DEPENDS
        ${Coverage_NAME}_cleanup_cpp
    )
    # hidden test target which depends on building all tests and cleaning test results
    add_custom_target(
      _run_tests_${PROJECT_NAME}_cpp_base_coverage_report
      DEPENDS
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info)
  else()
    # dummy targets for the case test and coverage are not enabled
    add_custom_target(_run_tests_${PROJECT_NAME}_python_base_coverage_report
      COMMAND "${CMAKE_COMMAND}" "-E" "echo" "Skipping python base coverage report target.")
    add_custom_target(_run_tests_${PROJECT_NAME}_cpp_base_coverage_report
      COMMAND "${CMAKE_COMMAND}" "-E" "echo" "Skipping cpp base coverage report target.")
  endif()

  # this dependency is to generate base report before tests
  add_dependencies(
    tests
    _run_tests_${PROJECT_NAME}_python_base_coverage_report
    _run_tests_${PROJECT_NAME}_cpp_base_coverage_report)
  # this dependency is to generate base report if there is no tests
  # add base coverage report generation as _run_tests_${PROJECT_NAME} dependency
  add_dependencies(
    _run_tests_${PROJECT_NAME}
    _run_tests_${PROJECT_NAME}_python_base_coverage_report
    _run_tests_${PROJECT_NAME}_cpp_base_coverage_report)

  # Create gtest C++ coverage report
  if(TARGET _run_tests_${PROJECT_NAME}_gtest)
    # create original gtest C++ coverage report
    add_custom_command(
      OUTPUT
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.original
      # Capturing lcov counters and generating report
      COMMAND
        ${CMAKE_COMMAND} -E make_directory
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS}
        --directory . --capture
        --output-file
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.original
      # Cleanup lcov for rostest
      COMMAND ${LCOV_PATH} --directory . --zerocounters
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
      DEPENDS
        _run_tests_${PROJECT_NAME}_gtest
    )
    add_custom_target(
      _create_coverage_report_${PROJECT_NAME}_gtest_cpp
      DEPENDS
        _run_tests_${PROJECT_NAME}_gtest
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.original
    )

    # refine gtest C++ coverage report
    add_custom_command(
      OUTPUT
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_gtest_cpp.info
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.total
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.removed
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.cleaned
      # add baseline counters
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS}
        -a ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info
        -a ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.original
        --output-file ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.total
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS} --remove
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.total
        ${LCOV_REMOVES}
        --output-file
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.removed
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS}
        --extract
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.removed
        "'*${REAL_SOURCE_DIR}*'"
        --output-file
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.cleaned
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.cleaned
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_gtest_cpp.info
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
      DEPENDS
        _run_tests_${PROJECT_NAME}_gtest
        _create_coverage_report_${PROJECT_NAME}_gtest_cpp
        ${PROJECT_BINARY_DIR}/gtest_cpp_coverage/${Coverage_NAME}_gtest_cpp.info.original
        _run_tests_${PROJECT_NAME}_cpp_base_coverage_report
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info
    )
    add_custom_target(
      ${Coverage_NAME}_gtest_cpp_info
      DEPENDS ${PROJECT_BINARY_DIR}/${Coverage_NAME}_gtest_cpp.info)
  else()
    # dummy targets for the case if there is no gtest
    add_custom_target(${Coverage_NAME}_gtest_cpp_info
      COMMAND "${CMAKE_COMMAND}" "-E" "echo" "Skipping gtest cpp coverage report target."
      DEPENDS _run_tests_${PROJECT_NAME})
  endif()

  # Create rostest C++ coverage report
  if(TARGET _run_tests_${PROJECT_NAME}_rostest)
    # create original rostest C++ coverage report
    add_custom_command(
      OUTPUT
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.original
      # Capturing lcov counters and generating report
      COMMAND
        ${CMAKE_COMMAND} -E make_directory
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS}
        --directory . --capture
        --output-file
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.original
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
      DEPENDS
        _run_tests_${PROJECT_NAME}_rostest
    )
    add_custom_target(
      _create_coverage_report_${PROJECT_NAME}_rostest_cpp
      DEPENDS
        _run_tests_${PROJECT_NAME}_rostest
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.original
    )

    # refine rostest C++ coverage report
    add_custom_command(
      OUTPUT
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_rostest_cpp.info
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.total
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.removed
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.cleaned
      # add baseline counters
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS}
        -a ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info
        -a ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.original
        --output-file
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.total
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS} --remove
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.total
        ${LCOV_REMOVES}
        --output-file
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.removed
      COMMAND
        ${LCOV_PATH} ${LCOV_EXTRA_FLAGS}
        --extract
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.removed
        "'*${REAL_SOURCE_DIR}*'"
        --output-file
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.cleaned
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.cleaned
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_rostest_cpp.info
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
      DEPENDS
        _run_tests_${PROJECT_NAME}_rostest
        _create_coverage_report_${PROJECT_NAME}_rostest_cpp
        ${PROJECT_BINARY_DIR}/rostest_cpp_coverage/${Coverage_NAME}_rostest_cpp.info.original
        _run_tests_${PROJECT_NAME}_cpp_base_coverage_report
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_base_cpp.info
    )
    add_custom_target(
      ${Coverage_NAME}_rostest_cpp_info
      DEPENDS ${PROJECT_BINARY_DIR}/${Coverage_NAME}_rostest_cpp.info)
  else()
    # dummy targets for the case if there is no rostest
    add_custom_target(${Coverage_NAME}_rostest_cpp_info
      COMMAND "${CMAKE_COMMAND}" "-E" "echo" "Skipping rostest cpp coverage report target."
      DEPENDS _run_tests_${PROJECT_NAME})
  endif()

  # run _create_coverage_report_${PROJECT_NAME}_gtest_cpp
  # before all rostest target tests_${PROJECT_NAME}_rostest
  if(TARGET tests_${PROJECT_NAME}_rostest AND
      TARGET _create_coverage_report_${PROJECT_NAME}_gtest_cpp)
    add_dependencies(
      tests_${PROJECT_NAME}_rostest
      _create_coverage_report_${PROJECT_NAME}_gtest_cpp
    )
  endif()

  # Create nosetests python coverage report
  if(TARGET _run_tests_${PROJECT_NAME}_nosetests)
    add_custom_command(
      OUTPUT
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_nosetests_python.xml
        ${PROJECT_BINARY_DIR}/nosetests_python_coverage/${Coverage_NAME}_nosetests_python.xml
      COMMAND
        ${CMAKE_COMMAND} -E make_directory
        ${PROJECT_BINARY_DIR}/nosetests_python_coverage/
      COMMAND
        ${PYTHON_COVERAGE_PATH} xml -o
        ${PROJECT_BINARY_DIR}/nosetests_python_coverage/${Coverage_NAME}_nosetests_python.xml
        ${INCLUDE_FLAGS} ${OMIT_FLAGS}
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${PROJECT_BINARY_DIR}/nosetests_python_coverage/${Coverage_NAME}_nosetests_python.xml
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_nosetests_python.xml
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${PROJECT_BINARY_DIR}/.coverage*
        ${PROJECT_BINARY_DIR}/nosetests_python_coverage/
      COMMAND
        ${CMAKE_COMMAND} -E remove 
        ${PROJECT_BINARY_DIR}/.coverage*
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}
      DEPENDS
        _run_tests_${PROJECT_NAME}_nosetests
    )
    add_custom_target(
      ${Coverage_NAME}_nosetests_python_xml
      DEPENDS
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_nosetests_python.xml
      )
  else()
    add_custom_target(${Coverage_NAME}_nosetests_python_xml
      COMMAND "${CMAKE_COMMAND}" "-E" "echo" "Skipping nosetests python coverage report target."
      DEPENDS _run_tests_${PROJECT_NAME})
  endif()

  # Create python pytests coverage report
  if(TARGET _run_tests_${PROJECT}_pytests)
    add_custom_command(
      OUTPUT
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_pytests_python.xml
        ${PROJECT_BINARY_DIR}/pytests_python_coverage/${Coverage_NAME}_pytests_python.xml
      COMMAND
        ${PYTHON_COVERAGE_PATH} combine || echo "WARNING: No pytests python coverage to combine"
      COMMAND
        ${PYTHON_COVERAGE_PATH} xml -o
        ${PROJECT_BINARY_DIR}/pytests_python_coverage/${Coverage_NAME}_pytests_python.xml
        ${INCLUDE_FLAGS} ${OMIT_FLAGS}
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${PROJECT_BINARY_DIR}/pytests_python_coverage/${Coverage_NAME}_pytests_python.xml
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_pytests_python.xml
      WORKING_DIRECTORY ${PROJECT_BINARY_DIR}/pytests_python_coverage
      DEPENDS
        _run_tests_${PROJECT_NAME}
    )
    add_custom_target(
      ${Coverage_NAME}_pytests_python_xml
      DEPENDS
        _run_tests_${PROJECT}_pytests
    )
  else()
    add_custom_target(${Coverage_NAME}_pytests_python_xml
      COMMAND "${CMAKE_COMMAND}" "-E" "echo" "Skipping pytests python coverage report target."
      DEPENDS _run_tests_${PROJECT_NAME})
  endif()

  # Create rostest python coverage report
  if(TARGET _run_tests_${PROJECT_NAME}_rostest)
    add_custom_command(
      OUTPUT
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_rostest_python.xml
        ${PROJECT_BINARY_DIR}/python_rostest_coverage/${Coverage_NAME}_rostest_python.xml
      # Rename .coverage file generated by nosetests to avoid overwriting during combine step
      COMMAND
        if [ -f ${PROJECT_BINARY_DIR}/.coverage ]\; then
          ${CMAKE_COMMAND} -E rename
          ${PROJECT_BINARY_DIR}/.coverage
          ${PROJECT_BINARY_DIR}/.coverage.nosetests\;
        fi
      COMMAND
        ${PYTHON_COVERAGE_PATH} combine || echo "WARNING: No rostest python coverage to combine"
      COMMAND
        ${CMAKE_COMMAND} -E make_directory
        ${PROJECT_BINARY_DIR}/rostest_python_coverage/
      COMMAND
        ${PYTHON_COVERAGE_PATH} xml  -o
        ${PROJECT_BINARY_DIR}/rostest_python_coverage/${Coverage_NAME}_rostest_python.xml
        ${INCLUDE_FLAGS} ${OMIT_FLAGS}
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${PROJECT_BINARY_DIR}/rostest_python_coverage//${Coverage_NAME}_rostest_python.xml
        ${PROJECT_BINARY_DIR}/${Coverage_NAME}_rostest_python.xml
      COMMAND
        ${CMAKE_COMMAND} -E copy
        ${COVERAGE_DIR}/.coverage*
        ${PROJECT_BINARY_DIR}/rostest_python_coverage/
      WORKING_DIRECTORY ${COVERAGE_DIR}
      DEPENDS
        _run_tests_${PROJECT_NAME}_rostest
        ${Coverage_NAME}_nosetests_python_xml
    )
    add_custom_target(
      ${Coverage_NAME}_rostest_python_xml
      DEPENDS ${PROJECT_BINARY_DIR}/${Coverage_NAME}_rostest_python.xml
    )
  else()
    add_custom_target(${Coverage_NAME}_rostest_python_xml
      COMMAND
        "${CMAKE_COMMAND}" "-E" "echo" "Skipping rostest python coverage report target."
      DEPENDS _run_tests_${PROJECT_NAME})
  endif()

  # add_custom_target works even DEPENDS files are not generated
  # when the files are generated by add_custom_command
  add_custom_target(${Coverage_NAME}
    DEPENDS
      ${Coverage_NAME}_gtest_cpp_info
      ${Coverage_NAME}_rostest_cpp_info
      ${Coverage_NAME}_nosetests_python_xml
      ${Coverage_NAME}_pytests_python_xml
      ${Coverage_NAME}_rostest_python_xml
    COMMENT "Processing code coverage counters and generating report."
  )

  # Show where to find the lcov info report
  add_custom_command(TARGET ${Coverage_NAME} POST_BUILD
    COMMAND ;
    COMMENT
      "Lcov code coverage info report saved in \
      ${PROJECT_BINARY_DIR}/${Coverage_NAME}_gtest_cpp.info,\
      ${PROJECT_BINARY_DIR}/${Coverage_NAME}_rostest_cpp.info."
  )

  # Show info where to find the Python report
  add_custom_command(TARGET ${Coverage_NAME} POST_BUILD
    COMMAND ;
    COMMENT
      "Python code coverage info saved in \
      ${PROJECT_BINARY_DIR}/${Coverage_NAME}_nosetests_python.xml,\
      ${PROJECT_BINARY_DIR}/${Coverage_NAME}_pytests_python.xml,\
      ${PROJECT_BINARY_DIR}/${Coverage_NAME}_rostest_python.xml."
  )

endfunction() # SETUP_TARGET_FOR_COVERAGE

function(APPEND_COVERAGE_COMPILER_FLAGS)
  # Set flags for all C++ builds
  set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} ${COVERAGE_COMPILER_FLAGS}" PARENT_SCOPE)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} ${COVERAGE_COMPILER_FLAGS}" PARENT_SCOPE)
  # Turn on coverage in python nosetests (see README for requirements on rostests)
  set(ENV{CATKIN_TEST_COVERAGE} "1")
  message(STATUS "Appending code coverage compiler flags: ${COVERAGE_COMPILER_FLAGS}")
endfunction() # APPEND_COVERAGE_COMPILER_FLAGS

option(ENABLE_COVERAGE_TESTING "Turn on coverage testing" OFF)
