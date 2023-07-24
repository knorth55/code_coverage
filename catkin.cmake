find_package(catkin REQUIRED)

catkin_package(CFG_EXTRAS code_coverage-extras.cmake)

## Install all cmake files
install(DIRECTORY cmake/Modules
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}/cmake)

install(DIRECTORY scripts
  DESTINATION ${CATKIN_PACKAGE_SHARE_DESTINATION}
  USE_SOURCE_PERMISSIONS)
