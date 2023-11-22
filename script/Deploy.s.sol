// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";

import {IPermit2} from "@permit2/src/src/interfaces/IPermit2.sol";
import "../contracts/JBOperatorStore.sol";
import "../contracts/JBProjects.sol";
import "../contracts/JBPrices.sol";
import "../contracts/JBFundingCycleStore.sol";
import "../contracts/JBDirectory.sol";
import "../contracts/JBTokenStore.sol";
import "../contracts/JBSplitsStore.sol";
import "../contracts/JBFundAccessConstraintsStore.sol";
import "../contracts/JBController3_1.sol";
import "../contracts/JBTerminalStore.sol";
import "../contracts/JBMultiTerminal.sol";

contract Deploy is Script {
    IPermit2 internal constant _PERMIT2 = IPermit2(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    // NOTICE: Make sure this is the correct forwarder address for the chain your deploying to.
    address internal constant _TRUSTED_FORWARDER =
        address(0xB2b5841DBeF766d4b521221732F9B618fCf34A87);

    JBOperatorStore _operatorStore;
    JBProjects _projects;
    JBPrices _prices;
    JBDirectory _directory;
    JBFundingCycleStore _fundingCycleStore;
    JBTokenStore _tokenStore;
    JBSplitsStore _splitsStore;
    JBFundAccessConstraintsStore _fundAccessConstraintsStore;
    JBController3_1 _controller;
    JBTerminalStore _terminalStore;
    JBMultiTerminal _multiTerminal;

    function _run(address _manager) internal {
        vm.broadcast();
        _deployContracts(_manager);
    }

    function _deployContracts(address _manager) internal {
        // 1
        _operatorStore = new JBOperatorStore();
        // 2
        _projects = new JBProjects(_operatorStore, _manager, _TRUSTED_FORWARDER);
        // 3
        _prices = new JBPrices(_operatorStore, _projects, _manager);
        address _directoryAddress = addressFrom(address(this), 5);
        //4
        _fundingCycleStore = new JBFundingCycleStore(
            IJBDirectory(_directoryAddress)
        );
        // 5
        _directory = new JBDirectory(
            _operatorStore,
            _projects,
            _fundingCycleStore,
            address(this)
        );
        _tokenStore = new JBTokenStore(
            _operatorStore,
            _projects,
            _directory,
            _fundingCycleStore
        );
        _splitsStore = new JBSplitsStore(_operatorStore, _projects, _directory, _TRUSTED_FORWARDER);
        _fundAccessConstraintsStore = new JBFundAccessConstraintsStore(
            _directory
        );
        _controller = new JBController3_1(
            _operatorStore,
            _projects,
            _directory,
            _fundingCycleStore,
            _tokenStore,
            _splitsStore,
            _fundAccessConstraintsStore,
            _TRUSTED_FORWARDER
        );
        _directory.setIsAllowedToSetFirstController(address(_controller), true);
        _directory.transferOwnership(_manager);
        _terminalStore = new JBTerminalStore(
            _directory,
            _fundingCycleStore,
            _prices
        );
        _multiTerminal = new JBMultiTerminal(
            _operatorStore,
            _projects,
            _directory,
            _splitsStore,
            _terminalStore,
            _PERMIT2,
            _TRUSTED_FORWARDER,
            _manager
        );
    }

    //https://ethereum.stackexchange.com/questions/24248/how-to-calculate-an-ethereum-contracts-address-during-its-creation-using-the-so
    function addressFrom(address _origin, uint256 _nonce)
        internal
        pure
        returns (address _address)
    {
        bytes memory data;
        if (_nonce == 0x00) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, bytes1(0x80));
        } else if (_nonce <= 0x7f) {
            data = abi.encodePacked(bytes1(0xd6), bytes1(0x94), _origin, uint8(_nonce));
        } else if (_nonce <= 0xff) {
            data =
                abi.encodePacked(bytes1(0xd7), bytes1(0x94), _origin, bytes1(0x81), uint8(_nonce));
        } else if (_nonce <= 0xffff) {
            data =
                abi.encodePacked(bytes1(0xd8), bytes1(0x94), _origin, bytes1(0x82), uint16(_nonce));
        } else if (_nonce <= 0xffffff) {
            data =
                abi.encodePacked(bytes1(0xd9), bytes1(0x94), _origin, bytes1(0x83), uint24(_nonce));
        } else {
            data =
                abi.encodePacked(bytes1(0xda), bytes1(0x94), _origin, bytes1(0x84), uint32(_nonce));
        }
        bytes32 hash = keccak256(data);
        assembly {
            mstore(0, hash)
            _address := mload(0)
        }
    }
}

// Ethereum
contract DeployEthereumMainnet is Deploy {
    function setUp() public {}

    address _manager = 0x823b92d6a4b2AED4b15675c7917c9f922ea8ADAD;

    function run() public {
        _run(_manager);
    }
}

contract DeployEthereumGoerli is Deploy {
    function setUp() public {}

    address _manager = 0x823b92d6a4b2AED4b15675c7917c9f922ea8ADAD;

    function run() public {
        _run(_manager);
    }
}

contract DeployEthereumSepolia is Deploy {
    function setUp() public {}

    address _manager = 0x823b92d6a4b2AED4b15675c7917c9f922ea8ADAD;

    function run() public {
        _run(_manager);
    }
}

// Optimism

contract DeployOptimismMainnet is Deploy {
    function setUp() public {}

    address _manager = 0x823b92d6a4b2AED4b15675c7917c9f922ea8ADAD;

    function run() public {
        _run(_manager);
    }
}

contract DeployOptimismTestnet is Deploy {
    function setUp() public {}

    address _manager = 0x823b92d6a4b2AED4b15675c7917c9f922ea8ADAD;

    function run() public {
        _run(_manager);
    }
}

// Polygon

contract DeployPolygonMainnet is Deploy {
    function setUp() public {}

    address _manager = 0x823b92d6a4b2AED4b15675c7917c9f922ea8ADAD;

    function run() public {
        _run(_manager);
    }
}

contract DeployPolygonMumbai is Deploy {
    function setUp() public {}

    address _manager = 0x823b92d6a4b2AED4b15675c7917c9f922ea8ADAD;

    function run() public {
        _run(_manager);
    }
}
