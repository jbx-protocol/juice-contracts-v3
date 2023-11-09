// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

// import {ERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
// import {IERC165} from '@openzeppelin/contracts/utils/introspection/ERC165.sol';
// import {IJBPaymentTerminal} from './../interfaces/IJBPaymentTerminal.sol';
// import {IJBSingleTokenPaymentTerminal} from './../interfaces/IJBSingleTokenPaymentTerminal.sol';

// /// @notice Generic terminal managing all inflows of funds into the protocol ecosystem for one token.
// abstract contract JBSingleTokenPaymentTerminal is ERC165, IJBSingleTokenPaymentTerminal {
//   //*********************************************************************//
//   // ---------------- public immutable stored properties --------------- //
//   //*********************************************************************//

//   /// @notice The token that this terminal accepts.
//   address public immutable override token;

//   /// @notice The number of decimals the token fixed point amounts are expected to have.
//   uint256 public immutable override decimals;

//   /// @notice The currency to use when resolving price feeds for this terminal.
//   uint256 public immutable override currency;

//   //*********************************************************************//
//   // ------------------------- external views -------------------------- //
//   //*********************************************************************//

//   //*********************************************************************//
//   // -------------------------- public views --------------------------- //
//   //*********************************************************************//

//   /// @notice Indicates if this contract adheres to the specified interface.
//   /// @dev See {IERC165-supportsInterface}.
//   /// @param _interfaceId The ID of the interface to check for adherance to.
//   /// @return A flag indicating if the provided interface ID is supported.
//   function supportsInterface(
//     bytes4 _interfaceId
//   ) public view virtual override(ERC165, IERC165) returns (bool) {
//     return
//       _interfaceId == type(IJBPaymentTerminal).interfaceId ||
//       _interfaceId == type(IJBSingleTokenPaymentTerminal).interfaceId ||
//       super.supportsInterface(_interfaceId);
//   }

//   //*********************************************************************//
//   // -------------------------- constructor ---------------------------- //
//   //*********************************************************************//

//   /// @param _token The token that this terminal manages.
//   /// @param _decimals The number of decimals the token fixed point amounts are expected to have.
//   /// @param _currency The currency that this terminal's token adheres to for price feeds.
//   constructor(address _token, uint256 _decimals, uint256 _currency) {
//     token = _token;
//     decimals = _decimals;
//     currency = _currency;
//   }
// }
