const {getDefaultConfig, mergeConfig} = require('@react-native/metro-config');
const path = require('path');
module.exports = mergeConfig(getDefaultConfig(__dirname), {resolver: {resolveRequest(context, moduleName, platform) { return context.resolveRequest(context, moduleName === 'react-native' || moduleName.startsWith('react-native/') ? moduleName.replace(/^react-native/, 'react-native-macos') : moduleName, platform); }, disableHierarchicalLookup: true, nodeModulesPaths: [path.join(__dirname, 'node_modules')]}, maxWorkers: 2});
