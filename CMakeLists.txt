cmake_minimum_required(VERSION 3.8)
project(code_coverage)

if($ENV{ROS_VERSION} EQUAL 2)
  include(ament.cmake)
else()
  include(catkin.cmake)
endif()
