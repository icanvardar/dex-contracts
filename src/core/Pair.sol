// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { SafeCastLib } from "vectorized/solady/utils/SafeCastLib.sol";

import { UQ112x112 } from "../libraries/UQ112x112.sol";
import { LPToken } from "./LPToken.sol";
import { IFactory } from "../interfaces/IFactory.sol";
import { ICallee } from "../interfaces/ICallee.sol";

/**
 * @title Pair
 * @dev The Pair contract represents a pair that holds liquidity tokens (LPToken).
 */
contract Pair is LPToken, ReentrancyGuard {
    using UQ112x112 for uint224;
    using SafeCastLib for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC CONSTANT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Minimum liquidity required for creating a pair
    uint256 public constant MINIMUM_LIQUIDITY = 10 ** 3;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Address of the factory contract
    address public factory;
    /// @notice Addresses of the token0 in the pair
    address public token0;
    /// @notice Addresses of the token1 in the pair
    address public token1;

    /*//////////////////////////////////////////////////////////////////////////
                                   PRIVATE STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Reserves of token0
    uint112 private reserve0;
    /// @notice Reserves of token1
    uint112 private reserve1;
    /// @notice Timestamp of the last block
    uint32 private blockTimestampLast;

    /*//////////////////////////////////////////////////////////////////////////
                                   PUBLIC STORAGE
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Price0 cumulative variable
    uint256 public price0CumulativeLast;
    /// @notice Price1 cumulative variable
    uint256 public price1CumulativeLast;
    /// @notice Product of reserves, as of immediately after the most recent liquidity event
    uint256 public kLast;

    /*//////////////////////////////////////////////////////////////////////////
                                   EVENTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Emitted when liquidity is added to the pair by a user.
    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    /// @notice Emitted when liquidity is removed from the pair by a user.
    event Burn(address indexed sender, uint256 amount0, uint256 amount1, address indexed to);
    /// @notice Emitted when a swap occurs between token0 and token1.
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    /// @notice Emitted when the reserves of the pair are updated.
    event Sync(uint112 reserve0, uint112 reserve1);

    /*//////////////////////////////////////////////////////////////////////////
                                   ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Throws an error indicating that the pair is locked.
    error Locked();
    /// @notice Throws an error indicating that an action is forbidden.
    error Forbidden();
    /// @notice Throws an error indicating an arithmetic overflow occurred.
    error Overflow();
    /// @notice Throws an error indicating that the amount of liquidity minted is insufficient.
    error InsufficientLiquidityMinted();
    /// @notice Throws an error indicating that the amount of liquidity burned is insufficient.
    error InsufficientLiquidityBurned();
    /// @notice Throws an error indicating that there is insufficient liquidity in the pair.
    error InsufficientLiquidity();
    /// @notice Throws an error indicating that the output amount is insufficient.
    error InsufficientOutputAmount();
    /// @notice Throws an error indicating that the input amount is insufficient.
    error InsufficientInputAmount();
    /// @notice Throws an error indicating that the recipient address is invalid.
    error InvalidTo();
    /// @notice Throws an error indicating that there is an issue with the product of reserves.
    error K();

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Contract constructor, sets the factory address.
     */
    constructor() {
        factory = msg.sender;
    }

    /*//////////////////////////////////////////////////////////////////////////
                         USER-FACING NON-CONSTANT FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Initializes the Pair contract with token0 and token1 addresses.
     * @param _token0 The address of the first token.
     * @param _token1 The address of the second token.
     */
    function initialize(address _token0, address _token1) external {
        if (msg.sender != factory) {
            revert Forbidden();
        }
        token0 = _token0;
        token1 = _token1;
    }

    /*//////////////////////////////////////////////////////////////////////////
                           USER-FACING CONSTANT FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Returns the current reserves and the last block timestamp.
     * @return _reserve0 The reserve of token0.
     * @return _reserve1 The reserve of token1.
     * @return _blockTimestampLast The timestamp of the last block.
     */
    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    /*//////////////////////////////////////////////////////////////////////////
                         USER-FACING NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Mint function. Mints liquidity tokens and handles initial conditions.
     * @param to Recipient address where minted liquidity tokens are transferred.
     * @return liquidity Amount of liquidity tokens minted and transferred to the recipient.
     */
    function mint(address to) external nonReentrant returns (uint256 liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        uint256 balance0 = IERC20(token0).balanceOf(address(this));
        uint256 balance1 = IERC20(token1).balanceOf(address(this));
        uint256 amount0 = balance0 - _reserve0;
        uint256 amount1 = balance1 - _reserve1;

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in
            // _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0 * amount1) - (MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            liquidity = Math.min((amount0 * _totalSupply) / _reserve0, (amount1 * _totalSupply) / _reserve1);
        }
        if (liquidity == 0) {
            revert InsufficientLiquidityMinted();
        }
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    /**
     * @dev Burn function. Burns liquidity tokens and transfers tokens back to the sender.
     * @param to Recipient address where tokens are transferred after burning liquidity.
     * @return amount0 Amount of token0 transferred to the recipient.
     * @return amount1 Amount of token1 transferred to the recipient.
     */
    function burn(address to) external nonReentrant returns (uint256 amount0, uint256 amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        uint256 balance0 = IERC20(_token0).balanceOf(address(this));
        uint256 balance1 = IERC20(_token1).balanceOf(address(this));
        uint256 liquidity = balanceOf(address(this));

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint256 _totalSupply = totalSupply(); // gas savings, must be defined here since totalSupply can update in
            // _mintFee
        amount0 = (liquidity * balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = (liquidity * balance1) / _totalSupply; // using balances ensures pro-rata distribution
        if (amount0 == 0 || amount1 == 0) {
            revert InsufficientLiquidityBurned();
        }
        _burn(address(this), liquidity);
        SafeERC20.safeTransfer(IERC20(_token0), to, amount0);
        SafeERC20.safeTransfer(IERC20(_token1), to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint256(reserve0) * reserve1; // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /**
     * @dev Swap function. Swaps tokens and performs a callback to the recipient contract.
     * @param amount0Out Amount of token0 to be sent out in the swap.
     * @param amount1Out Amount of token1 to be sent out in the swap.
     * @param to Recipient address where tokens are sent.
     * @param data Additional data for the recipient contract's callback function.
     */
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external nonReentrant {
        if (amount0Out == 0 && amount1Out == 0) {
            revert InsufficientOutputAmount();
        }
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        if (amount0Out > _reserve0 || amount1Out > _reserve1) {
            revert InsufficientLiquidity();
        }

        uint256 balance0;
        uint256 balance1;
        {
            // scope for _token{0,1}, avoids stack too deep errors
            address _token0 = token0;
            address _token1 = token1;
            if (to == _token0 || to == _token1) {
                revert InvalidTo();
            }
            if (amount0Out > 0) SafeERC20.safeTransfer(IERC20(_token0), to, amount0Out); // optimistically transfer
                // tokens
            if (amount1Out > 0) SafeERC20.safeTransfer(IERC20(_token1), to, amount1Out); // optimistically transfer
                // tokens
            if (data.length > 0) ICallee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20(_token0).balanceOf(address(this));
            balance1 = IERC20(_token1).balanceOf(address(this));
        }
        uint256 amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint256 amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        if (amount0In == 0 && amount1In == 0) {
            revert InsufficientInputAmount();
        }
        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint256 balance0Adjusted = (balance0 * 1000) - (amount0In * 3);
            uint256 balance1Adjusted = (balance1 * 1000) - (amount1In * 3);
            if (balance0Adjusted * balance1Adjusted < uint256(_reserve0) * _reserve1 * (1000 ** 2)) {
                revert K();
            }
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /**
     * @dev Skim function. Transfers excess tokens (beyond reserves) to the specified recipient.
     * @param to Recipient address where excess tokens are transferred.
     */
    function skim(address to) external nonReentrant {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        SafeERC20.safeTransfer(IERC20(_token0), to, IERC20(_token0).balanceOf(address(this)) - reserve0);
        SafeERC20.safeTransfer(IERC20(_token1), to, IERC20(_token1).balanceOf(address(this)) - reserve1);
    }

    /**
     * @dev Sync function. Forces reserves to match balances.
     */
    function sync() external nonReentrant {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }

    /*//////////////////////////////////////////////////////////////////////////
                         PRIVATE NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Updates reserves and, on the first call per block, price accumulators.
     * @param balance0 Current balance of token0 in the pair contract.
     * @param balance1 Current balance of token1 in the pair contract.
     * @param _reserve0 Reserve balance of token0.
     * @param _reserve1 Reserve balance of token1.
     */
    function _update(uint256 balance0, uint256 balance1, uint112 _reserve0, uint112 _reserve1) private {
        if (balance0 > type(uint112).max || balance1 > type(uint112).max) {
            revert Overflow();
        }
        uint32 blockTimestamp = (block.timestamp % 2 ** 32).toUint32();
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint256(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint256(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = balance0.toUint112();
        reserve1 = balance1.toUint112();
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    /**
     * @dev Mint function. If fee is enabled, mints liquidity equivalent to 1/6th of the growth in sqrt(k).
     * @param _reserve0 Reserve balance of token0.
     * @param _reserve1 Reserve balance of token1.
     * @return feeOn Boolean indicating whether the fee is enabled.
     */
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
        address feeTo = IFactory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint256 _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint256 rootK = Math.sqrt(uint256(_reserve0) * _reserve1);
                uint256 rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint256 numerator = totalSupply() * (rootK - rootKLast);
                    uint256 denominator = (rootK * 5) + (rootKLast);
                    uint256 liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }
}
