//
//  Generated file. Do not edit.
//

import FlutterMacOS
import Foundation

import file_picker
import neurosdk2
import path_provider_foundation
import record_macos
import universal_ble

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  FilePickerPlugin.register(with: registry.registrar(forPlugin: "FilePickerPlugin"))
  Neurosdk2Plugin.register(with: registry.registrar(forPlugin: "Neurosdk2Plugin"))
  PathProviderPlugin.register(with: registry.registrar(forPlugin: "PathProviderPlugin"))
  RecordMacOsPlugin.register(with: registry.registrar(forPlugin: "RecordMacOsPlugin"))
  UniversalBlePlugin.register(with: registry.registrar(forPlugin: "UniversalBlePlugin"))
}
