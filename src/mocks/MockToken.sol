pragma solidity 0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Trip Token", "TRIP") {}

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}
