//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <libbird/libbird_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) libbird_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "LibbirdPlugin");
  libbird_plugin_register_with_registrar(libbird_registrar);
}
