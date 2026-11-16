cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES C CXX)

# Define the application target. To change its name, change BINARY_NAME in the
# top-level CMakeLists.txt, not the value here, or `flutter run` will no longer
# work.
#
# Any new source files that you add to the application should be added here.
add_executable(${BINARY_NAME}
  "main.cc"
  "my_application.cc"
  "glass.cc"
  "${FLUTTER_MANAGED_DIR}/generated_plugin_registrant.cc"
)

# Apply the standard set of build settings. This can be removed for applications
# that need different build settings.
apply_standard_settings(${BINARY_NAME})

# Add preprocessor definitions for the application ID.
add_definitions(-DAPPLICATION_ID="${APPLICATION_ID}")

# Add dependency libraries. Add any application-specific dependencies here.
target_link_libraries(${BINARY_NAME} PRIVATE flutter)
target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::GTK)

# Frosted Glass's blur behind the window (glass.cc): X11's hint, and Wayland's
# ext-background-effect-v1 (its client code made by wayland-scanner from wayland-protocols 1.45's
# staging/ext-background-effect/ext-background-effect-v1.xml). Each only where its library is.
pkg_check_modules(X11 IMPORTED_TARGET x11)
if(X11_FOUND)
  target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::X11)
endif()
pkg_check_modules(WAYLAND_CLIENT IMPORTED_TARGET wayland-client)
if(WAYLAND_CLIENT_FOUND)
  target_sources(${BINARY_NAME} PRIVATE "ext-background-effect-v1-protocol.c")
  target_compile_definitions(${BINARY_NAME} PRIVATE HAVE_BACKGROUND_EFFECT)
  target_link_libraries(${BINARY_NAME} PRIVATE PkgConfig::WAYLAND_CLIENT)
endif()

target_include_directories(${BINARY_NAME} PRIVATE "${CMAKE_SOURCE_DIR}")
