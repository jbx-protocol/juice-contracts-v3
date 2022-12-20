enum TokenType {
  ERC20,
  ERC721,
  ERC1155
}

contract PlatformDiscountManager {
  address[] public tokens;
  /**
   * @notice Maps token addresses that qualify users for a discount to a discount description
   */
  mapping(address => uint256) public discounts;

  /**
   * @notice
   *
   * @param _token Token address ownership of which qualifies a user to the given discount.
   * @param _tokenType Token type: ERC20, ERC721, etc. Defined in `TokenType` enum.
   * @param _tokenBalance Minimum token balance to quilify for the discount.
   * @param _discount Discount percentage in bps.
   */
  function registerDiscount(
    address _token,
    TokenType _tokenType,
    uint256 _tokenBalance,
    uint256 _discount
  ) external {
    // _tokenType: 8b
    // _tokenBalance: 96b
    // _discount: 14b
  }

  function removeDiscount(address _token) external {
    //
  }

  function getPrice(address _actor, uint256 _fee) external view returns (uint256 price) {
    price = _fee;
  }

  function getDiscountInfo(
    address _token
  ) external view returns (uint256 tokenBalance, uint256 discount) {
    tokenBalance = 0;
    discount = 0;
  }
}
