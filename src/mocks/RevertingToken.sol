pragma solidity 0.8.27;

import {MockToken} from "./MockToken.sol";

contract RevertingToken is MockToken {
    error ForcedFailure();

    bool public failTransfer;
    bool public failTransferFrom;

    function setFailTransfer(bool value) external {
        failTransfer = value;
    }

    function setFailTransferFrom(bool value) external {
        failTransferFrom = value;
    }

    function transfer(address recipient, uint256 amount) public override returns (bool) {
        if (failTransfer) revert ForcedFailure();
        return super.transfer(recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        if (failTransferFrom) revert ForcedFailure();
        return super.transferFrom(sender, recipient, amount);
    }
}
