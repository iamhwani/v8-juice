#!/do/not/make
# To be included by plugin makefiles
########################################################################
# Before including this file define:
#  PLUGIN_NAME=the base plugin name (e.g. myplugin)
#  PLUGIN_OBJ=list of .o files for the plugin
#  PLUGIN_LDADD=optional list of extra linker arguments
########################################################################
ifeq (,$(PLUGIN_NAME))
$(error PLUGIN_NAME must be defined before including this file!)
endif

ifeq (,$(PLUGIN_OBJECTS))
$(error PLUGIN_OBJECTS must be defined before including this file!)
endif

package.dist_files += $(wildcard *.cpp *.cc *.h *.hpp)

########################################################################
# Build DLL...
PLUGIN_DLL_NAME := v8-juice-$(PLUGIN_NAME)
c-dlls.list := $(PLUGIN_DLL_NAME)
$(PLUGIN_DLL_NAME).DLL.VERSION := $(V8JUICE_VERSION_DOTTED)
$(PLUGIN_DLL_NAME).DLL.OBJECTS := $(PLUGIN_OBJECTS)
$(PLUGIN_DLL_NAME).DLL.LDADD ?= $(PLUGIN_LDADD)
include $(toc2.dirs.makefiles)/c-dlls.make
all: $($(PLUGIN_DLL_NAME).DLL)
# end DLL rules
########################################################################
