// solidity-coverage configuration file.
//
// https://www.npmjs.com/package/solidity-coverage

module.exports = {
  skipFiles: [
    'abstract/',
    'enums/',
    'interfaces/',
    'libraries/',
    'structs/',
    'system_tests/',
    'contracts/extensions/interfaces/',
    'contracts/extensions/NFT/interfaces/'],
  configureYulOptimizer: true,
  measureStatementCoverage: false
};
