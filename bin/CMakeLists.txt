add_subdirectory(ai)
add_subdirectory(game)

if(IOS_BUILD)
    file(GLOB SCRIPT_FILES "${CMAKE_CURRENT_SOURCE_DIR}/scripts/*")
    target_sources(openttd PRIVATE ${SCRIPT_FILES})
    set_source_files_properties(${SCRIPT_FILES}
            PROPERTIES
            MACOSX_PACKAGE_LOCATION Resources/scripts
    )
endif()
