// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface IPoolService {
    function addLiquidity(uint256 amount, address onBehalfOf, uint256 referralCode) external;
    function removeLiquidity(uint256 amount, address to) external returns (uint256);
    function underlyingToken() external view returns (address);
    function dieselToken() external view returns (address);
    function borrowAPY_RAY() external view returns (uint256);
    function totalBorrowed() external view returns (uint256);
    function withdrawFee() external view returns (uint256);
    function getDieselRate_RAY() external view returns (uint256);
    function expectedLiquidity() external view returns (uint256);
    function availableLiquidity() external view returns (uint256);
    function interestRateModel() external view returns (address);
}

interface IAirdropDistributor {
    function claim(uint256 index, address account, uint256 totalAmount, bytes32[] calldata merkleProof) external;
}
