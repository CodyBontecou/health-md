const {getDefaultConfig, mergeConfig} = require('@react-native/metro-config');
module.exports = mergeConfig(getDefaultConfig(__dirname), {
  resolver: {disableHierarchicalLookup: true, nodeModulesPaths: [require('path').join(__dirname, 'node_modules')]},
  maxWorkers: 2,
});
