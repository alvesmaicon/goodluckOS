# 2Ship finds tinyxml2 and spdlog installed; SoH gets them through Torch. Fetch the same versions, static.
include(FetchContent)
set(tinyxml2_BUILD_TESTING OFF)
FetchContent_Declare(tinyxml2
    GIT_REPOSITORY https://github.com/leethomason/tinyxml2.git
    GIT_TAG 10.0.0
    OVERRIDE_FIND_PACKAGE)
FetchContent_Declare(spdlog
    GIT_REPOSITORY https://github.com/gabime/spdlog.git
    GIT_TAG v1.16.0
    OVERRIDE_FIND_PACKAGE)
FetchContent_MakeAvailable(tinyxml2 spdlog)
# OTRExporter includes tinyxml2.h without linking it, as if it were in /usr/include
include_directories(${tinyxml2_SOURCE_DIR})
