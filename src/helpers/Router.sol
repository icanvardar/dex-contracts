// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IFactory } from "../interfaces/IFactory.sol";
import { IPair } from "../interfaces/IPair.sol";
import { IRouter } from "../interfaces/IRouter.sol";
import { IWETH } from "../interfaces/IWETH.sol";
import { RouterLib } from "../libraries/RouterLib.sol";

/**
 * @title Router
 * @dev Implementation of the IRouter interface. Handles token swaps and liquidity operations.
 */
contract Router is IRouter {
    /*//////////////////////////////////////////////////////////////////////////
                                  PUBLIC CONSTANT
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Address of the recipient for trading fees
    address public immutable factory;
    /// @notice Address of the recipient for trading fees
    address public immutable WETH;

    /*//////////////////////////////////////////////////////////////////////////
                                  ERRORS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Throws an error indicating that the deadline for a transaction has expired
    error DeadlineExpired();
    /// @notice Throws an error indicating that the provided amount of token A is insufficient
    error InsufficientAAmount();
    /// @notice Throws an error indicating that the provided amount of token B is insufficient
    error InsufficientBAmount();
    /// @notice Throws an error indicating that the output amount is insufficient
    error InsufficientOutputAmount();
    /// @notice Throws an error indicating that the input amount is excessive
    error ExcessiveInputAmount();
    /// @notice Throws an error indicating that the provided amounts for token A and B do not match
    error MismatchedAmounts();
    /// @notice Throws an error indicating that the provided token path is invalid
    error InvalidPath();
    /// @notice Throws an error indicating that it's unable to send Ether
    error UnableToSendEther();
    /// @notice Throws an error indicating that it's unable to transfer WETH
    error UnableToTransferWETH();
    /// @notice Throws an error indicating that the sender is not allowed to perform the action
    error WrongSender();

    /*//////////////////////////////////////////////////////////////////////////
                                  MODIFIER
    //////////////////////////////////////////////////////////////////////////*/

    // Modifier to check if the deadline has not expired.
    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) {
            revert DeadlineExpired();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Constructor to initialize the Router with the factory and WETH addresses.
     * @param factoryAddress Address of the factory contract.
     * @param wethAddress Address of the Wrapped Ether (WETH) contract.
     */
    constructor(address factoryAddress, address wethAddress) {
        factory = factoryAddress;
        WETH = wethAddress;
    }

    /*//////////////////////////////////////////////////////////////////////////
                         USER-FACING NON-CONSTANT FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    // Fallback function to reject Ether from being sent directly to the contract.
    receive() external payable {
        if (msg.sender != WETH) {
            revert WrongSender();
        }
    }

    /**
     * @dev Adds liquidity to a pair of tokens.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B.
     * @param amountADesired Desired amount of token A.
     * @param amountBDesired Desired amount of token B.
     * @param amountAMin Minimum acceptable amount of token A.
     * @param amountBMin Minimum acceptable amount of token B.
     * @param to Address to receive the liquidity tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @return amountA Amount of token A added to the liquidity pool.
     * @return amountB Amount of token B added to the liquidity pool.
     * @return liquidity Amount of liquidity tokens minted.
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = RouterLib.pairFor(factory, tokenA, tokenB);
        SafeERC20.safeTransferFrom(IERC20(tokenA), msg.sender, pair, amountA);
        SafeERC20.safeTransferFrom(IERC20(tokenB), msg.sender, pair, amountB);
        liquidity = IPair(pair).mint(to);
    }

    /**
     * @dev Adds liquidity to a pair involving Wrapped Ether (WETH).
     * @param token Address of the ERC-20 token.
     * @param amountTokenDesired Desired amount of the ERC-20 token.
     * @param amountTokenMin Minimum acceptable amount of the ERC-20 token.
     * @param amountETHMin Minimum acceptable amount of Ether.
     * @param to Address to receive the liquidity tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @return amountToken Amount of ERC-20 token added to the liquidity pool.
     * @return amountETH Amount of Ether added to the liquidity pool.
     * @return liquidity Amount of liquidity tokens minted.
     */
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH, uint256 liquidity)
    {
        (amountToken, amountETH) =
            _addLiquidity(token, WETH, amountTokenDesired, msg.value, amountTokenMin, amountETHMin);
        address pair = RouterLib.pairFor(factory, token, WETH);
        SafeERC20.safeTransferFrom(IERC20(token), msg.sender, pair, amountToken);
        IWETH(WETH).deposit{ value: amountETH }();
        bool sent = IWETH(WETH).transfer(pair, amountETH);
        if (!sent) {
            revert UnableToTransferWETH();
        }
        liquidity = IPair(pair).mint(to);

        if (msg.value > amountETH) {
            (bool success,) = msg.sender.call{ value: msg.value - amountETH }("");

            if (!success) {
                revert UnableToSendEther();
            }
        }
    }

    /**
     * @dev Removes liquidity from a pair of tokens.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B.
     * @param liquidity Amount of liquidity tokens to remove.
     * @param amountAMin Minimum acceptable amount of token A.
     * @param amountBMin Minimum acceptable amount of token B.
     * @param to Address to receive the underlying tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @return amountA Amount of token A received.
     * @return amountB Amount of token B received.
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint256 amountA, uint256 amountB)
    {
        address pair = RouterLib.pairFor(factory, tokenA, tokenB);
        IPair(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = IPair(pair).burn(to);
        (address token0,) = RouterLib.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        if (amountA < amountAMin) {
            revert InsufficientAAmount();
        }
        if (amountB < amountBMin) {
            revert InsufficientBAmount();
        }
    }

    /**
     * @dev Removes liquidity from a pair involving Wrapped Ether (WETH).
     * @param token Address of the ERC-20 token.
     * @param liquidity Amount of liquidity tokens to remove.
     * @param amountTokenMin Minimum acceptable amount of the ERC-20 token.
     * @param amountETHMin Minimum acceptable amount of Ether.
     * @param to Address to receive the underlying tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @return amountToken Amount of ERC-20 token received.
     * @return amountETH Amount of Ether received.
     */
    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint256 amountToken, uint256 amountETH)
    {
        (amountToken, amountETH) =
            removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        SafeERC20.safeTransfer(IERC20(token), to, amountToken);
        IWETH(WETH).withdraw(amountETH);

        (bool success,) = to.call{ value: amountETH }("");
        if (!success) {
            revert UnableToSendEther();
        }
    }

    /**
     * @dev Removes liquidity from a pair with permit for both tokens.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B.
     * @param liquidity Amount of liquidity tokens to remove.
     * @param amountAMin Minimum acceptable amount of token A.
     * @param amountBMin Minimum acceptable amount of token B.
     * @param to Address to receive the underlying tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @param approveMax Boolean indicating whether to approve the maximum amount.
     * @param v v component of the permit signature.
     * @param r r component of the permit signature.
     * @param s s component of the permit signature.
     * @return amountA Amount of token A received.
     * @return amountB Amount of token B received.
     */
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        virtual
        override
        returns (uint256 amountA, uint256 amountB)
    {
        address pair = RouterLib.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    /**
     * @dev Removes liquidity from a pair involving Wrapped Ether (WETH) with permit for both tokens.
     * @param token Address of the ERC-20 token.
     * @param liquidity Amount of liquidity tokens to remove.
     * @param amountTokenMin Minimum acceptable amount of the ERC-20 token.
     * @param amountETHMin Minimum acceptable amount of Ether.
     * @param to Address to receive the underlying tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @param approveMax Boolean indicating whether to approve the maximum amount.
     * @param v v component of the permit signature.
     * @param r r component of the permit signature.
     * @param s s component of the permit signature.
     * @return amountToken Amount of ERC-20 token received.
     * @return amountETH Amount of Ether received.
     */
    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        virtual
        override
        returns (uint256 amountToken, uint256 amountETH)
    {
        address pair = RouterLib.pairFor(factory, token, WETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountETH) = removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    /**
     * @dev Removes liquidity from a pair, supporting fee-on-transfer tokens.
     * @param token Address of the ERC-20 token.
     * @param liquidity Amount of liquidity tokens to remove.
     * @param amountTokenMin Minimum acceptable amount of the ERC-20 token.
     * @param amountETHMin Minimum acceptable amount of Ether.
     * @param to Address to receive the underlying tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @return amountETH Amount of Ether received.
     */
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        public
        virtual
        override
        ensure(deadline)
        returns (uint256 amountETH)
    {
        (, amountETH) = removeLiquidity(token, WETH, liquidity, amountTokenMin, amountETHMin, address(this), deadline);
        SafeERC20.safeTransfer(IERC20(token), to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);

        (bool success,) = to.call{ value: amountETH }("");
        if (!success) {
            revert UnableToSendEther();
        }
    }

    /**
     * @dev Removes liquidity from a pair involving Wrapped Ether (WETH) with permit for both tokens,
     * supporting fee-on-transfer tokens.
     * @param token Address of the ERC-20 token.
     * @param liquidity Amount of liquidity tokens to remove.
     * @param amountTokenMin Minimum acceptable amount of the ERC-20 token.
     * @param amountETHMin Minimum acceptable amount of Ether.
     * @param to Address to receive the underlying tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @param approveMax Boolean indicating whether to approve the maximum amount.
     * @param v v component of the permit signature.
     * @param r r component of the permit signature.
     * @param s s component of the permit signature.
     * @return amountETH Amount of Ether received.
     */
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
        virtual
        override
        returns (uint256 amountETH)
    {
        address pair = RouterLib.pairFor(factory, token, WETH);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        IPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountETH = removeLiquidityETHSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountETHMin, to, deadline
        );
    }

    /**
     * @dev Swaps an exact amount of input tokens for an equivalent amount of output tokens.
     * @param amountIn Amount of input tokens.
     * @param amountOutMin Minimum acceptable amount of output tokens.
     * @param path An array of token addresses describing the route of the swap.
     * @param to Address to receive the output tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @return amounts An array of the actual input and output amounts swapped.
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = RouterLib.getAmountsOut(factory, amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        SafeERC20.safeTransferFrom(
            IERC20(path[0]), msg.sender, RouterLib.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    /**
     * @dev Swaps an exact amount of input tokens for a maximum amount of output tokens.
     * @param amountOut Maximum acceptable amount of output tokens.
     * @param amountInMax Maximum acceptable amount of input tokens.
     * @param path An array of token addresses describing the route of the swap.
     * @param to Address to receive the output tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @return amounts An array of the actual input and output amounts swapped.
     */
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        amounts = RouterLib.getAmountsIn(factory, amountOut, path);
        if (amounts[0] > amountInMax) {
            revert ExcessiveInputAmount();
        }
        SafeERC20.safeTransferFrom(
            IERC20(path[0]), msg.sender, RouterLib.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    /**
     * @dev Swaps an exact amount of Ether for a minimum amount of output tokens.
     * @param amountOutMin Minimum acceptable amount of output tokens.
     * @param path An array of token addresses describing the route of the swap.
     * @param to Address to receive the output tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @return amounts An array of the actual input and output amounts swapped.
     */
    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[0] != WETH) {
            revert InvalidPath();
        }
        amounts = RouterLib.getAmountsOut(factory, msg.value, path);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        IWETH(WETH).deposit{ value: amounts[0] }();
        bool sent = IWETH(WETH).transfer(RouterLib.pairFor(factory, path[0], path[1]), amounts[0]);
        if (!sent) {
            revert UnableToTransferWETH();
        }
        _swap(amounts, path, to);
    }

    /**
     * @dev Swaps an exact amount of input tokens for a maximum amount of Ether.
     * @param amountOut Maximum acceptable amount of Ether.
     * @param amountInMax Maximum acceptable amount of input tokens.
     * @param path An array of token addresses describing the route of the swap.
     * @param to Address to receive the Ether.
     * @param deadline Timestamp deadline for the transaction.
     * @return amounts An array of the actual input and output amounts swapped.
     */
    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[path.length - 1] != WETH) {
            revert InvalidPath();
        }
        amounts = RouterLib.getAmountsIn(factory, amountOut, path);
        if (amounts[0] > amountInMax) {
            revert ExcessiveInputAmount();
        }
        SafeERC20.safeTransferFrom(
            IERC20(path[0]), msg.sender, RouterLib.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);

        (bool success,) = to.call{ value: amounts[amounts.length - 1] }("");
        if (!success) {
            revert UnableToSendEther();
        }
    }

    /**
     * @dev Swaps an exact amount of input tokens for a minimum amount of Ether.
     * @param amountIn Amount of input tokens.
     * @param amountOutMin Minimum acceptable amount of Ether.
     * @param path An array of token addresses describing the route of the swap.
     * @param to Address to receive the Ether.
     * @param deadline Timestamp deadline for the transaction.
     * @return amounts An array of the actual input and output amounts swapped.
     */
    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[path.length - 1] != WETH) {
            revert InvalidPath();
        }
        amounts = RouterLib.getAmountsOut(factory, amountIn, path);
        if (amounts[amounts.length - 1] < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        SafeERC20.safeTransferFrom(
            IERC20(path[0]), msg.sender, RouterLib.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);

        (bool success,) = to.call{ value: amounts[amounts.length - 1] }("");
        if (!success) {
            revert UnableToSendEther();
        }
    }

    /**
     * @dev Swaps an exact amount of Ether for a maximum amount of output tokens.
     * @param amountOut Maximum acceptable amount of output tokens.
     * @param path An array of token addresses describing the route of the swap.
     * @param to Address to receive the output tokens.
     * @param deadline Timestamp deadline for the transaction.
     * @return amounts An array of the actual input and output amounts swapped.
     */
    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        if (path[0] != WETH) {
            revert InvalidPath();
        }
        amounts = RouterLib.getAmountsIn(factory, amountOut, path);
        if (amounts[0] > msg.value) {
            revert ExcessiveInputAmount();
        }
        IWETH(WETH).deposit{ value: amounts[0] }();
        bool sent = IWETH(WETH).transfer(RouterLib.pairFor(factory, path[0], path[1]), amounts[0]);
        if (!sent) {
            revert UnableToTransferWETH();
        }
        _swap(amounts, path, to);

        if (msg.value > amounts[0]) {
            (bool success,) = msg.sender.call{ value: msg.value - amounts[0] }("");
            if (!success) {
                revert UnableToSendEther();
            }
        }
    }

    /**
     * @dev Swaps an exact amount of input tokens for a maximum amount of output tokens, supporting fee-on-transfer
     * tokens.
     * @param amountIn Amount of input tokens.
     * @param amountOutMin Minimum acceptable amount of output tokens.
     * @param path An array of token addresses describing the route of the swap.
     * @param to Address to receive the output tokens.
     * @param deadline Timestamp deadline for the transaction.
     */
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        SafeERC20.safeTransferFrom(IERC20(path[0]), msg.sender, RouterLib.pairFor(factory, path[0], path[1]), amountIn);
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore < amountOutMin) {
            revert InsufficientOutputAmount();
        }
    }

    /**
     * @dev Swaps an exact amount of Ether for a minimum amount of output tokens, supporting fee-on-transfer tokens.
     * @param amountOutMin Minimum acceptable amount of output tokens.
     * @param path An array of token addresses describing the route of the swap.
     * @param to Address to receive the output tokens.
     * @param deadline Timestamp deadline for the transaction.
     */
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        payable
        virtual
        override
        ensure(deadline)
    {
        if (path[0] != WETH) {
            revert InvalidPath();
        }
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{ value: amountIn }();
        bool sent = IWETH(WETH).transfer(RouterLib.pairFor(factory, path[0], path[1]), amountIn);
        if (!sent) {
            revert UnableToTransferWETH();
        }
        uint256 balanceBefore = IERC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        if (IERC20(path[path.length - 1]).balanceOf(to) - balanceBefore < amountOutMin) {
            revert InsufficientOutputAmount();
        }
    }

    /**
     * @dev Swaps an exact amount of input tokens for a maximum amount of Ether, supporting fee-on-transfer tokens.
     * @param amountIn Amount of input tokens.
     * @param amountOutMin Minimum acceptable amount of Ether.
     * @param path An array of token addresses describing the route of the swap.
     * @param to Address to receive the Ether.
     * @param deadline Timestamp deadline for the transaction.
     */
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        if (path[path.length - 1] != WETH) {
            revert InvalidPath();
        }
        SafeERC20.safeTransferFrom(IERC20(path[0]), msg.sender, RouterLib.pairFor(factory, path[0], path[1]), amountIn);
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        if (amountOut < amountOutMin) {
            revert InsufficientOutputAmount();
        }
        IWETH(WETH).withdraw(amountOut);

        (bool success,) = to.call{ value: amountOut }("");
        if (!success) {
            revert UnableToSendEther();
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                           USER-FACING CONSTANT FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Provides the expected amount of tokens received for a given input amount, reserveA, and reserveB.
     * @param amountA Input amount.
     * @param reserveA Reserve of token A in the pair.
     * @param reserveB Reserve of token B in the pair.
     * @return amountB Expected amount of tokens received.
     */
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    )
        public
        pure
        virtual
        override
        returns (uint256 amountB)
    {
        return RouterLib.quote(amountA, reserveA, reserveB);
    }

    /**
     * @dev Provides the expected output amount for a given input amount and reserves.
     * @param amountIn Input amount.
     * @param reserveIn Reserve of the input token.
     * @param reserveOut Reserve of the output token.
     * @return amountOut Expected output amount.
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    )
        public
        pure
        virtual
        override
        returns (uint256 amountOut)
    {
        return RouterLib.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /**
     * @dev Provides the required input amount for a given output amount and reserves.
     * @param amountOut Desired output amount.
     * @param reserveIn Reserve of the input token.
     * @param reserveOut Reserve of the output token.
     * @return amountIn Required input amount.
     */
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    )
        public
        pure
        virtual
        override
        returns (uint256 amountIn)
    {
        return RouterLib.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    /**
     * @dev Provides the array of expected output amounts for a given input amount and token swap path.
     * @param amountIn Input amount.
     * @param path An array of token addresses describing the route of the swap.
     * @return amounts Array of expected output amounts.
     */
    function getAmountsOut(
        uint256 amountIn,
        address[] memory path
    )
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return RouterLib.getAmountsOut(factory, amountIn, path);
    }

    /**
     * @dev Provides the array of required input amounts for a given output amount and token swap path.
     * @param amountOut Desired output amount.
     * @param path An array of token addresses describing the route of the swap.
     * @return amounts Array of required input amounts.
     */
    function getAmountsIn(
        uint256 amountOut,
        address[] memory path
    )
        public
        view
        virtual
        override
        returns (uint256[] memory amounts)
    {
        return RouterLib.getAmountsIn(factory, amountOut, path);
    }

    /*//////////////////////////////////////////////////////////////////////////
                           INTERNAL NON-CONSTANT FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to add liquidity to a pair.
     * @param tokenA Address of token A.
     * @param tokenB Address of token B.
     * @param amountADesired Desired amount of token A.
     * @param amountBDesired Desired amount of token B.
     * @param amountAMin Minimum acceptable amount of token A.
     * @param amountBMin Minimum acceptable amount of token B.
     * @return amountA Amount of token A added to the liquidity pool.
     * @return amountB Amount of token B added to the liquidity pool.
     */
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    )
        internal
        virtual
        returns (uint256 amountA, uint256 amountB)
    {
        if (IFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IFactory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = RouterLib.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = RouterLib.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                if (amountBOptimal < amountBMin) {
                    revert InsufficientBAmount();
                }
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = RouterLib.quote(amountBDesired, reserveB, reserveA);
                if (amountAOptimal > amountADesired) {
                    revert MismatchedAmounts();
                }
                if (amountAOptimal < amountAMin) {
                    revert InsufficientAAmount();
                }
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    /**
     * @dev Executes a multi-step token swap along the provided path.
     * @param amounts An array of token amounts representing the swap path.
     * @param path An array of token addresses describing the route of the swap.
     * @param _to The address to receive the final swapped tokens.
     * @dev This internal function performs a series of swaps between adjacent tokens in the given path.
     * It is used to implement various external swap functions in the contract.
     */
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = RouterLib.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? RouterLib.pairFor(factory, output, path[i + 2]) : _to;
            IPair(RouterLib.pairFor(factory, input, output)).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    /**
     * @dev Swaps the given tokens in the provided path while supporting fee-on-transfer tokens.
     * @param path An array of token addresses describing the route of the swap.
     * @param _to The address to receive the swapped tokens.
     * @dev This function is internal and is used to perform swaps with fee-on-transfer tokens.
     * It ensures proper handling of tokens that implement transfer fees on each transfer,
     * providing support for swapping them in a multi-step path.
     */
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = RouterLib.sortTokens(input, output);
            IPair pair = IPair(RouterLib.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) =
                    input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
                amountInput = IERC20(input).balanceOf(address(pair)) - reserveInput;
                amountOutput = RouterLib.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? RouterLib.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
}
