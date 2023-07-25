find_package(ament_cmake REQUIRED)

install(DIRECTORY cmake
  DESTINATION share/${PROJECT_NAME})
install(DIRECTORY scripts/
  DESTINATION lib/${PROJECT_NAME}
  USE_SOURCE_PERMISSIONS)

ament_package(CONFIG_EXTRAS cmake/code_coverage-extras.cmake.in)
