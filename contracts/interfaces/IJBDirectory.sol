// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IJBFundingCycleStore} from "./IJBFundingCycleStore.sol";
import {IJBTerminal} from "./terminal/IJBTerminal.sol";
import {IJBPaymentTerminal} from "./terminal/IJBPaymentTerminal.sol";
import {IJBProjects} from "./IJBProjects.sol";

interface IJBDirectory {
    event SetController(uint256 indexed projectId, address indexed controller, address caller);

    event AddTerminal(
        uint256 indexed projectId, IJBTerminal indexed terminal, address caller
    );

    event SetTerminals(uint256 indexed projectId, IJBTerminal[] terminals, address caller);

    event SetPrimaryTerminal(
        uint256 indexed projectId,
        address indexed token,
        IJBTerminal indexed terminal,
        address caller
    );

    event SetIsAllowedToSetFirstController(address indexed addr, bool indexed flag, address caller);

    function projects() external view returns (IJBProjects);

    function fundingCycleStore() external view returns (IJBFundingCycleStore);

    function controllerOf(uint256 projectId) external view returns (address);

    function isAllowedToSetFirstController(address account) external view returns (bool);

    function terminalsOf(uint256 projectId) external view returns (IJBTerminal[] memory);

    function isTerminalOf(uint256 projectId, IJBTerminal terminal)
        external
        view
        returns (bool);

    function primaryTerminalOf(uint256 projectId, address token)
        external
        view
        returns (IJBPaymentTerminal);

    function setControllerOf(uint256 projectId, address controller) external;

    function setTerminalsOf(uint256 projectId, IJBTerminal[] calldata terminals) external;

    function setPrimaryTerminalOf(uint256 projectId, address token, IJBPaymentTerminal terminal)
        external;

    function setIsAllowedToSetFirstController(address account, bool flag) external;
}
