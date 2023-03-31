// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.8.19;

import {BaseStrategy, StrategyParams} from "@yearnvaults/contracts/BaseStrategy.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IPoolService, IAirdropDistributor} from "./interfaces/Gearbox/GearboxV2.sol";
import "./interfaces/ySwaps/ITradeFactory.sol";
import "./interfaces/IERC20Metadata.sol";

contract Strategy is BaseStrategy {
    using SafeERC20 for IERC20;
    using Address for address;

    IPoolService public poolService;
    IAirdropDistributor internal constant airdropDistributor =
        IAirdropDistributor(0xA7Df60785e556d65292A2c9A077bb3A8fBF048BC);
    IERC20 public diesel;
    IERC20 public constant reward = IERC20(0xBa3335588D9403515223F109EdC4eB7269a9Ab5D);

    uint256 internal constant RAY = 1e27;
    uint256 private constant max = type(uint256).max;

    event Cloned(address indexed clone);

    bool internal isOriginal = true;

    address public tradeFactory;

    constructor(address _vault, address _poolService) BaseStrategy(_vault) {
        _initializeStrategy(_poolService);
    }

    function _initializeStrategy(address _poolService) internal {
        require(address(poolService) == address(0), "!already initialized");
        poolService = IPoolService(_poolService);
        require(poolService.underlyingToken() == address(want), "!wrong token");
        diesel = IERC20(poolService.dieselToken());
        IERC20(want).safeApprove(_poolService, type(uint256).max);
    }

    function initialize(address _vault, address _strategist, address _rewards, address _keeper, address _poolService)
        external
    {
        _initialize(_vault, _strategist, _rewards, _keeper);
        _initializeStrategy(_poolService);
    }

    function clone(address _vault, address _strategist, address _rewards, address _keeper, address _poolService)
        external
        returns (address newStrategy)
    {
        require(isOriginal, "!clone");
        bytes20 addressBytes = bytes20(address(this));
        assembly {
            let clone_code := mload(0x40)
            mstore(clone_code, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(add(clone_code, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            newStrategy := create(0, clone_code, 0x37)
        }
        Strategy(newStrategy).initialize(_vault, _strategist, _rewards, _keeper, _poolService);

        emit Cloned(newStrategy);
    }

    function name() external view override returns (string memory) {
        return string(abi.encodePacked("StrategyGearboxV2Lender", IERC20Metadata(address(want)).symbol()));
    }

    function estimatedTotalAssets() public view override returns (uint256) {
        return balanceOfWant() + dieselToWant(underlyingBalanceStored());
    }

    function prepareReturn(uint256 _debtOutstanding)
        internal
        override
        returns (uint256 _profit, uint256 _loss, uint256 _debtPayment)
    {
        // @note Grab the estimate total debt from the vault
        uint256 _vaultDebt = vault.strategies(address(this)).totalDebt;
        uint256 _totalAssets = estimatedTotalAssets();

        _profit = _totalAssets > _vaultDebt ? _totalAssets - _vaultDebt : 0;

        // @note Free up _debtOutstanding + our profit, and make any necessary adjustments to the accounting.
        uint256 _amountNeeded = _debtOutstanding + _profit;
        uint256 _balanceOfWant = balanceOfWant();

        if (_amountNeeded > _balanceOfWant) {
            _withdraw(_amountNeeded - _balanceOfWant);
        }

        _loss = (_vaultDebt > _totalAssets ? _vaultDebt - _totalAssets : 0);
        uint256 _liquidWant = balanceOfWant();

        // @note calculate _debtPayment - enough to pay profit (partial or full) only
        if (_liquidWant <= _profit) {
            _profit = _liquidWant;
            _debtPayment = 0;
            // @note calculate _debtPayment - enough to pay for all profit and _debtOutstanding (partial or full)
        } else {
            _debtPayment = Math.min(_liquidWant - _profit, _debtOutstanding);
        }
        // @note calculate final p&l
        if (_loss > _profit) {
            _loss = _loss - _profit;
            _profit = 0;
        } else {
            _profit = _profit - _loss;
            _loss = 0;
        }
    }

    function adjustPosition(uint256 _debtOutstanding) internal override {
        uint256 _looseWant = balanceOfWant();
        if (_looseWant > _debtOutstanding) {
            uint256 _amountToDeposit = _looseWant - _debtOutstanding;
            _deposit(_amountToDeposit);
        }
    }

    function liquidatePosition(uint256 _amountNeeded)
        internal
        override
        returns (uint256 _liquidatedAmount, uint256 _loss)
    {
        uint256 _liquidAssets = balanceOfWant();

        if (_liquidAssets < _amountNeeded) {
            (_loss) = _withdraw(_amountNeeded);
            _liquidAssets = balanceOfWant();
        }

        _liquidatedAmount = Math.min(_amountNeeded, _liquidAssets);
        require(_amountNeeded >= _liquidatedAmount + _loss, "!check");
    }

    function liquidateAllPositions() internal override returns (uint256) {
        uint256 _underlyingBalanceStored = underlyingBalanceStored();
        if (_underlyingBalanceStored > 0) {
            _withdraw(_underlyingBalanceStored);
        }
        return balanceOfWant();
    }

    function prepareMigration(address _newStrategy) internal override {
        diesel.safeTransfer(_newStrategy, underlyingBalanceStored());
        uint256 _balanceOfReward = balanceOfReward();
        if (_balanceOfReward > 0) {
            reward.safeTransfer(_newStrategy, _balanceOfReward);
        }
    }

    function protectedTokens() internal view override returns (address[] memory) {}

    function ethToWant(uint256 _ethAmount) public view override returns (uint256) {}

    // ADD TRIGGERS

    // --------- UTILITY & HELPER FUNCTIONS ------------
    function _withdraw(uint256 amount) internal returns (uint256 _loss) {
        // @note will only attempt to withdraw available liquidity
        uint256 _preWithdrawWant = balanceOfWant();
        poolService.removeLiquidity(Math.min(availableLiquidity(), wantToDiesel(amount)), address(this));
        uint256 _liquidatedAmount = balanceOfWant() - _preWithdrawWant;
        uint256 _potentialLoss = amount - _liquidatedAmount;
        uint256 _underlyingBalanceStoredinWant = underlyingBalanceStoredinWant();
        _loss = _potentialLoss > _underlyingBalanceStoredinWant ? _potentialLoss - _underlyingBalanceStoredinWant : 0;
    }

    function _deposit(uint256 amount) internal {
        poolService.addLiquidity(amount, address(this), 0);
    }

    function wantToDiesel(uint256 _amount) public view returns (uint256) {
        return (_amount * RAY) / poolService.getDieselRate_RAY(); // @note scalling up to keep precision
    }

    function dieselToWant(uint256 _diesel) public view returns (uint256) {
        return (_diesel * poolService.getDieselRate_RAY()) / RAY;
    }

    function availableLiquidity() public view returns (uint256) {
        return diesel.totalSupply() - poolService.totalBorrowed();
    }

    function underlyingBalanceStored() public view returns (uint256) {
        return diesel.balanceOf(address(this));
    }

    function underlyingBalanceStoredinWant() public view returns (uint256) {
        return dieselToWant(underlyingBalanceStored());
    }

    function balanceOfWant() public view returns (uint256) {
        return want.balanceOf(address(this));
    }

    function balanceOfReward() public view returns (uint256) {
        return reward.balanceOf(address(this));
    }

    // ----------------- MANUAL FUNCTIONS ---------------------

    // @note To be called externally, with index, totalAmount and merkleProof provided by Gearbox
    function claimGearReward(uint256 _index, uint256 _amount, bytes32[] calldata _merkleProof)
        external
        onlyVaultManagers
    {
        airdropDistributor.claim(_index, address(this), _amount, _merkleProof);
    }

    // ----------------- YSWAPS FUNCTIONS ---------------------

    function setTradeFactory(address _tradeFactory) external onlyGovernance {
        if (tradeFactory != address(0)) {
            _removeTradeFactoryPermissions();
        }

        reward.safeApprove(_tradeFactory, max);
        ITradeFactory tf = ITradeFactory(_tradeFactory);
        tf.enable(address(reward), address(want));
        tradeFactory = _tradeFactory;
    }

    function removeTradeFactoryPermissions() external onlyEmergencyAuthorized {
        _removeTradeFactoryPermissions();
    }

    function _removeTradeFactoryPermissions() internal {
        reward.safeApprove(tradeFactory, 0);
        tradeFactory = address(0);
    }
}
