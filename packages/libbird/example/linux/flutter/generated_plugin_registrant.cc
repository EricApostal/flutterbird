//
//  Generated file. Do not edit.
//

// clang-format off

#include "generated_plugin_registrant.h"

#include <ladybird/ladybird_plugin.h>

void fl_register_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) ladybird_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "LadybirdPlugin");
  ladybird_plugin_register_with_registrar(ladybird_registrar);
}
