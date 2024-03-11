// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import { Test } from "forge-std/Test.sol";

import { WETH } from "solady/tokens/WETH.sol";

import { Pair } from "../../src/core/Pair.sol";
import { Router } from "../../src/helpers/Router.sol";
import { PairFactory } from "../../src/core/PairFactory.sol";
import { RouterLib } from "../../src/libraries/RouterLib.sol";

import { MockERC20 } from "../mocks/MockERC20.sol";

contract RouterTest is Test {
    uint256 public constant TOKEN_A_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;
    uint256 public constant TOKEN_B_TOTAL_SUPPLY = 115_792_089_237_316_195_423_570_985e18;
    bytes32 internal constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    address public feeTo;
    address public sender;
    uint256 public deadline;
    address public feeToSetter;

    Pair internal pair;
    WETH internal weth;
    Router internal router;
    MockERC20 internal tokenA;
    MockERC20 internal tokenB;
    PairFactory internal pairFactory;

    //Ordered pair adress
    MockERC20 public token0;
    MockERC20 public token1;

    receive() external payable { }

    function setUp() public {
        sender = vm.addr(1);
        feeTo = makeAddr("feeTo");
        deadline = block.timestamp + 1;
        feeToSetter = makeAddr("feeToSetter");

        tokenA = new MockERC20("tokenA", "TA");
        tokenB = new MockERC20("tokenB", "TB");
        weth = new WETH();

        weth.deposit{ value: 20e18 }();

        pairFactory = new PairFactory(feeToSetter);
        router = new Router(address(pairFactory), address(weth));

        address createdPairAddress = pairFactory.createPair(address(tokenA), address(tokenB));
        pair = Pair(createdPairAddress);

        (address _token0, address _token1) = RouterLib.sortTokens(address(tokenA), address(tokenB));
        token0 = MockERC20(_token0);
        token1 = MockERC20(_token1);

        assertEq(pair.token0(), _token0);
        assertEq(pair.token1(), _token1);
        assertEq(pairFactory.getPair(_token0, _token1), createdPairAddress);
    }

    function test_ShouldBeSuccess_initialize() public {
        pairFactory = new PairFactory(feeToSetter);
        router = new Router(address(pairFactory), address(weth));

        assertEq(router.factory(), address(pairFactory));
        assertEq(router.WETH(), address(weth));
    }

    function test_ShouldBeSuccess_createsPair_addLiquidity() public {
        MockERC20 tokenC = new MockERC20("tokenC", "TC");
        MockERC20 tokenD = new MockERC20("tokenD", "TD");

        uint256 token0ApprovedAmt = 1e18;
        uint256 token1approveAmount = 1e18;

        tokenC.approve(address(router), token0ApprovedAmt);
        tokenD.approve(address(router), token1approveAmount);

        (uint256 amountA, uint256 amountB, uint256 liquidity) = router.addLiquidity(
            address(tokenC),
            address(tokenD),
            token0ApprovedAmt,
            token1approveAmount,
            token0ApprovedAmt,
            token1approveAmount,
            address(this),
            deadline
        );

        address pairAddress = pairFactory.getPair(address(tokenC), address(tokenD));
        address createdPairAddress = RouterLib.pairFor(address(pairFactory), address(tokenC), address(tokenD));

        assertEq(pairAddress, createdPairAddress);
        assertEq(tokenC.balanceOf(address(pairAddress)), amountA);
        assertEq(tokenD.balanceOf(address(pairAddress)), amountB);
        assertEq(Pair(pairAddress).balanceOf(address(this)), liquidity);
        assertEq(Pair(pairAddress).balanceOf(address(0)), Pair(pairAddress).MINIMUM_LIQUIDITY());
        assertEq(Pair(pairAddress).totalSupply(), liquidity + Pair(pairAddress).MINIMUM_LIQUIDITY());
    }

    function test_ShouldBeSuccess_amountBOptimalIsOk_addLiquidity() public {
        uint256 token0transferAmount = 1e18;
        uint256 token1transferAmount = 1e18;
        (,, uint256 firstLiquidity) = _addLiquidity(token0transferAmount, token1transferAmount);

        uint256 token0ApprovedAmt = 1e18;
        uint256 token1approveAmount = 2e18;

        token0.approve(address(router), token0ApprovedAmt);
        token1.approve(address(router), token1approveAmount);

        (uint256 amountA, uint256 amountB, uint256 secondLiquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            token0ApprovedAmt,
            token1approveAmount,
            1e18,
            1e17,
            address(this),
            deadline
        );

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();
        uint256 amountBOptimal = RouterLib.quote(token0ApprovedAmt, _reserve0, _reserve1);

        assertEq(amountA, token0ApprovedAmt);
        assertEq(amountB, amountBOptimal);
        assertEq(pair.balanceOf(address(this)), firstLiquidity + secondLiquidity);
    }

    function test_ShouldBeSuccess_amountBOptimalIsTooHigh_addLiquidity() public {
        uint256 token0transferAmount = 10e18;
        uint256 token1transferAmount = 5e18;
        (,, uint256 firstLiquidity) = _addLiquidity(token0transferAmount, token1transferAmount);

        uint256 token0ApprovedAmt = 2e18;
        uint256 token1approveAmount = 1e18;

        token0.approve(address(router), token0ApprovedAmt);
        token1.approve(address(router), token1approveAmount);

        (uint112 _reserve0, uint112 _reserve1,) = pair.getReserves();
        uint256 amountBOptimal = RouterLib.quote(token0ApprovedAmt, _reserve0, _reserve1);

        uint256 nonOptimal = amountBOptimal - 1e17;

        uint256 amountAOptimal = RouterLib.quote(nonOptimal, _reserve1, _reserve0);

        (uint256 amountA, uint256 amountB, uint256 secondLiquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            token0ApprovedAmt,
            nonOptimal,
            amountAOptimal,
            token1approveAmount,
            address(this),
            deadline
        );

        assertEq(amountA, amountAOptimal);
        assertEq(amountB, nonOptimal);
        assertEq(pair.balanceOf(address(this)), firstLiquidity + secondLiquidity);
    }

    function test_ShouldBeSuccess_noPair_addLiquidityETH() public {
        uint256 token0ApprovedAmt = 1e18;
        uint256 wethApprovedAmt = 2e18;

        token0.approve(address(router), token0ApprovedAmt);
        weth.approve(address(router), wethApprovedAmt);

        (uint256 amountA, uint256 amountB, uint256 secondLiquidity) = router.addLiquidityETH{ value: 2e18 }(
            address(token0), token0ApprovedAmt, 1e18, 1e17, address(this), deadline
        );

        address pairAddress = pairFactory.getPair(address(token0), address(weth));

        (uint112 _reserve0, uint112 _reserve1,) = Pair(pairAddress).getReserves();
        uint256 amountBOptimal = RouterLib.quote(token0ApprovedAmt, _reserve0, _reserve1);

        assertEq(amountA, token0ApprovedAmt);
        assertEq(amountB, amountBOptimal);
        assertEq(Pair(pairAddress).balanceOf(address(this)), secondLiquidity);
    }

    function test_ShouldBeSuccess_removeLiquidity() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            _addLiquidity(token0TransferAmount, token1TransferAmount);

        pair.approve(address(router), liquidity);

        (uint256 _amountA, uint256 _amountB) = router.removeLiquidity(
            address(token0),
            address(token1),
            liquidity,
            token0TransferAmount - pair.MINIMUM_LIQUIDITY(),
            token1TransferAmount - pair.MINIMUM_LIQUIDITY(),
            address(this),
            deadline
        );

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        assertEq(uint112(token0.balanceOf(address(pair))), reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), reserve1);

        assertEq(pair.balanceOf(address(this)), 0);
        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - amountA + _amountA);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - amountB + _amountB);
    }

    function test_ShouldBeSuccess_removeLiquidityETH() public {
        uint256 token0ApprovedAmt = 1e18;
        uint256 wethApprovedAmt = 1e18;

        token0.approve(address(router), token0ApprovedAmt);
        weth.approve(address(router), wethApprovedAmt);

        (uint256 amountA,, uint256 liquidity) = router.addLiquidityETH{ value: 1e18 }(
            address(token0), token0ApprovedAmt, 1e18, 1e18, address(this), deadline
        );

        address pairAddress = pairFactory.getPair(address(token0), address(weth));

        Pair(pairAddress).approve(address(router), liquidity);

        (uint256 _amountA, uint256 _amountB) = router.removeLiquidity(
            address(token0),
            address(weth),
            liquidity,
            token0ApprovedAmt - pair.MINIMUM_LIQUIDITY(),
            wethApprovedAmt - pair.MINIMUM_LIQUIDITY(),
            address(this),
            deadline
        );

        (uint256 reserve0, uint256 reserve1,) = Pair(pairAddress).getReserves();
        assertEq(uint112(token0.balanceOf(address(pairAddress))), reserve0);
        assertEq(uint112(weth.balanceOf(address(pairAddress))), reserve1);

        assertEq(Pair(pairAddress).balanceOf(address(this)), 0);
        assertEq(Pair(pairAddress).totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - amountA + _amountA);
        assertEq(weth.balanceOf(address(this)), 20e18 + _amountB);
    }

    function test_ShouldBeSuccess_partially_removeLiquidity() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            _addLiquidity(token0TransferAmount, token1TransferAmount);

        uint256 calculateLiquidity = (liquidity * 3) / 10;
        pair.approve(address(router), calculateLiquidity);

        (uint256 _amountA, uint256 _amountB) = router.removeLiquidity(
            address(tokenA),
            address(tokenB),
            calculateLiquidity,
            0.3 ether - 3e16,
            0.3 ether - 3e16,
            address(this),
            deadline
        );

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        assertEq(uint112(token0.balanceOf(address(pair))), reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), reserve1);

        assertEq(pair.balanceOf(address(this)), liquidity - calculateLiquidity);
        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - amountA + _amountA);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - amountB + _amountB);
        assertEq(pair.totalSupply(), (liquidity + pair.MINIMUM_LIQUIDITY()) - calculateLiquidity);
    }

    function test_ShouldBeSuccess_removeLiquidityWithPermit() public {
        token0.transfer(sender, 5e18);
        token1.transfer(sender, 5e18);

        vm.startPrank(sender);

        token0.approve(address(router), 1e18);
        token1.approve(address(router), 1e18);

        (uint256 amountA, uint256 amountB, uint256 liquidity) =
            router.addLiquidity(address(token0), address(token1), 1e18, 1e18, 1e18, 1e18, sender, deadline);

        bytes32 permitMeesageHash =
            _getPermitHash(pair, sender, address(router), liquidity, pair.nonces(sender), deadline);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);

        (uint256 _amountA, uint256 _amountB) = router.removeLiquidityWithPermit(
            address(token0),
            address(token1),
            liquidity,
            1e18 - pair.MINIMUM_LIQUIDITY(),
            1e18 - pair.MINIMUM_LIQUIDITY(),
            sender,
            deadline,
            false,
            v,
            r,
            s
        );

        (uint256 reserve0, uint256 reserve1,) = pair.getReserves();
        assertEq(uint112(token0.balanceOf(address(pair))), reserve0);
        assertEq(uint112(token1.balanceOf(address(pair))), reserve1);

        assertEq(pair.balanceOf(sender), 0);
        assertEq(pair.totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(token0.balanceOf(sender), 5e18 - amountA + _amountA);
        assertEq(token1.balanceOf(sender), 5e18 - amountB + _amountB);
    }

    function test_ShouldBeSuccess_removeLiquidityETHWithPermit() public {
        vm.deal(sender, 1e18);
        token0.transfer(sender, 5e18);
        weth.transfer(sender, 5e18);

        vm.startPrank(sender);

        token0.approve(address(router), 1e18);
        weth.approve(address(router), 1e18);

        (uint256 amountA,, uint256 liquidity) =
            router.addLiquidityETH{ value: 1e18 }(address(token0), 1e18, 1e18, 1e18, sender, deadline);

        address pairAddress = pairFactory.getPair(address(token0), address(weth));

        bytes32 permitMeesageHash = _getPermitHash(
            Pair(pairAddress), sender, address(router), liquidity, Pair(pairAddress).nonces(sender), deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);

        (uint256 _amountA,) = router.removeLiquidityETHWithPermit(
            address(token0),
            liquidity,
            1e18 - Pair(pairAddress).MINIMUM_LIQUIDITY(),
            1e18 - Pair(pairAddress).MINIMUM_LIQUIDITY(),
            sender,
            deadline,
            false,
            v,
            r,
            s
        );

        (uint256 reserve0, uint256 reserve1,) = Pair(pairAddress).getReserves();
        assertEq(uint112(token0.balanceOf(address(pairAddress))), reserve0);
        assertEq(uint112(weth.balanceOf(address(pairAddress))), reserve1);

        assertEq(Pair(pairAddress).balanceOf(sender), 0);
        assertEq(Pair(pairAddress).totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(token0.balanceOf(sender), 5e18 - amountA + _amountA);
        assertEq(weth.balanceOf(sender), 5e18);
    }

    function test_ShouldBeSuccess_removeLiquidityETHSupportingFeeOnTransferTokens() public {
        uint256 token0ApprovedAmt = 1e18;
        uint256 wethApprovedAmt = 1e18;

        token0.approve(address(router), token0ApprovedAmt);
        weth.approve(address(router), wethApprovedAmt);

        (,, uint256 liquidity) = router.addLiquidityETH{ value: 1e18 }(
            address(token0), token0ApprovedAmt, 1e18, 1e18, address(this), deadline
        );

        address pairAddress = pairFactory.getPair(address(token0), address(weth));

        Pair(pairAddress).approve(address(router), liquidity);

        (uint256 _amountEth) = router.removeLiquidityETHSupportingFeeOnTransferTokens(
            address(token0),
            liquidity,
            token0ApprovedAmt - pair.MINIMUM_LIQUIDITY(),
            wethApprovedAmt - pair.MINIMUM_LIQUIDITY(),
            address(this),
            deadline
        );

        (uint256 reserve0, uint256 reserve1,) = Pair(pairAddress).getReserves();
        assertEq(uint112(token0.balanceOf(address(pairAddress))), reserve0);
        assertEq(uint112(weth.balanceOf(address(pairAddress))), reserve1);

        assertEq(Pair(pairAddress).balanceOf(address(this)), 0);
        assertEq(Pair(pairAddress).totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 + _amountEth);
        assertEq(weth.balanceOf(address(this)), 20e18);
    }

    function test_ShouldBeSuccess_removeLiquidityETHWithPermitSupportingFeeOnTransferTokens() public {
        vm.deal(sender, 1e18);
        token0.transfer(sender, 5e18);
        weth.transfer(sender, 5e18);

        vm.startPrank(sender);

        token0.approve(address(router), 1e18);
        weth.approve(address(router), 1e18);

        (uint256 amountA,, uint256 liquidity) =
            router.addLiquidityETH{ value: 1e18 }(address(token0), 1e18, 1e18, 1e18, sender, deadline);

        address pairAddress = pairFactory.getPair(address(token0), address(weth));

        bytes32 permitMeesageHash = _getPermitHash(
            Pair(pairAddress), sender, address(router), liquidity, Pair(pairAddress).nonces(sender), deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, permitMeesageHash);

        (uint256 _amountETH) = router.removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
            address(token0),
            liquidity,
            1e18 - Pair(pairAddress).MINIMUM_LIQUIDITY(),
            1e18 - Pair(pairAddress).MINIMUM_LIQUIDITY(),
            sender,
            deadline,
            false,
            v,
            r,
            s
        );

        (uint256 reserve0, uint256 reserve1,) = Pair(pairAddress).getReserves();
        assertEq(uint112(token0.balanceOf(address(pairAddress))), reserve0);
        assertEq(uint112(weth.balanceOf(address(pairAddress))), reserve1);

        assertEq(Pair(pairAddress).balanceOf(sender), 0);
        assertEq(Pair(pairAddress).totalSupply(), pair.MINIMUM_LIQUIDITY());
        assertEq(token0.balanceOf(sender), 5e18 - amountA + _amountETH);
        assertEq(weth.balanceOf(sender), 5e18);
    }

    function test_ShouldBeSuccess_swapExactTokensForTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        token0.approve(address(router), 3e17);
        router.swapExactTokensForTokens(3e17, 1e17, path, address(this), deadline);

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 - 3e17);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 2e18);
        assertEq(weth.balanceOf(address(this)), 20e18 + amount2Out);
    }

    function test_ShouldBeSuccess_swapTokensForExactTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        token0.approve(address(router), 3e17);
        router.swapTokensForExactTokens(amount2Out, 3e17, path, address(this), deadline);

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 - 3e17);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 2e18);
        assertEq(weth.balanceOf(address(this)), 20e18 + amount2Out);
    }

    function test_ShouldBeSuccess_swapExactETHForTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(token1);
        path[2] = address(token0);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        weth.approve(address(router), 3e17);
        router.swapExactETHForTokens{ value: 3e17 }(1e17, path, address(this), deadline);

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 + amount2Out);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 2e18);
        assertEq(weth.balanceOf(address(this)), 20e18);
    }

    function test_ShouldBeSuccess_swapTokensForExactETH() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        token0.approve(address(router), 3e17);
        router.swapTokensForExactETH(amount2Out, 3e17, path, address(this), deadline);

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 - 3e17);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 2e18);
        assertEq(weth.balanceOf(address(this)), 20e18);
    }

    function test_ShouldBeSuccess_swapExactTokensForETH() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        token0.approve(address(router), 3e17);
        router.swapExactTokensForETH(3e17, 1e17, path, address(this), deadline);

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 - 3e17);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 2e18);
        assertEq(weth.balanceOf(address(this)), 20e18);
    }

    function test_ShouldBeSuccess_swapETHForExactTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(token1);
        path[2] = address(token0);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        weth.approve(address(router), 3e17);
        router.swapETHForExactTokens{ value: 3e17 }(amount2Out, path, address(this), deadline);

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 + amount2Out);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 2e18);
        assertEq(weth.balanceOf(address(this)), 20e18);
    }

    function test_ShouldBeSuccess_swapExactTokensForTokensSupportingFeeOnTransferTokens() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);

        token0.approve(address(router), 3e17);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(3e17, amount1Out, path, address(this), deadline);

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 - 3e17);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 1e18 + amount1Out);
    }

    function test_ShouldBeSuccess_swapExactETHForTokensSupportingFeeOnTransferTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(token1);
        path[2] = address(token0);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        weth.approve(address(router), 3e17);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: 3e17 }(1e17, path, address(this), deadline);

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 + amount2Out);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 2e18);
        assertEq(weth.balanceOf(address(this)), 20e18);
    }

    function test_ShouldBeSuccess_swapExactTokensForETHSupportingFeeOnTransferTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        token0.approve(address(router), 3e17);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(3e17, 1e17, path, address(this), deadline);

        assertEq(token0.balanceOf(address(this)), TOKEN_A_TOTAL_SUPPLY - 1e18 - 3e17);
        assertEq(token1.balanceOf(address(this)), TOKEN_B_TOTAL_SUPPLY - 2e18);
        assertEq(weth.balanceOf(address(this)), 20e18);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      REVERTS
    //////////////////////////////////////////////////////////////////////////*/

    function test_Revert_insufficientBAmount_addLiquidity() public {
        uint256 token0transferAmount = 1e18;
        uint256 token1transferAmount = 1e18;
        _addLiquidity(token0transferAmount, token1transferAmount);

        uint256 token0ApprovedAmt = 1e18;
        uint256 token1approveAmount = 2e18;

        token0.approve(address(router), token0ApprovedAmt);
        token1.approve(address(router), token1approveAmount);

        vm.expectRevert(Router.InsufficientBAmount.selector);
        router.addLiquidity(
            address(token0),
            address(token1),
            token0ApprovedAmt,
            token1approveAmount,
            token0ApprovedAmt,
            token1approveAmount,
            address(this),
            deadline
        );
    }

    function test_Revert_insufficientAAmount_addLiquidity() public {
        uint256 token0transferAmount = 1e18;
        uint256 token1transferAmount = 1e18;
        _addLiquidity(token0transferAmount, token1transferAmount);

        uint256 token0ApprovedAmt = 1e18;
        uint256 token1approveAmount = 2e18;

        token0.approve(address(router), token0ApprovedAmt);
        token1.approve(address(router), token1approveAmount);

        vm.expectRevert(Router.InsufficientAAmount.selector);
        router.addLiquidity(
            address(token0),
            address(token1),
            token1approveAmount,
            token0ApprovedAmt,
            token1approveAmount,
            token0ApprovedAmt,
            address(this),
            deadline
        );
    }

    //function test_Revert_UnableToTransferWETH_addLiquidityETH() public { }

    function test_Revert_UnableToSendEther_addLiquidityETH() public {
        address erc20Contract = makeAddr("erc20Contract");
        vm.etch(erc20Contract, "1");

        vm.deal(erc20Contract, 5e18);
        token0.transfer(erc20Contract, 5e18);
        weth.transfer(erc20Contract, 5e18);

        vm.startPrank(erc20Contract);

        uint256 token0ApprovedAmt = 1e18;
        uint256 wethApprovedAmt = 1e18;

        token0.approve(address(router), token0ApprovedAmt);
        weth.approve(address(router), wethApprovedAmt);

        router.addLiquidityETH{ value: 1e18 }(address(token0), token0ApprovedAmt, 1e18, 1e18, erc20Contract, deadline);

        token0.approve(address(router), 1e18);
        weth.approve(address(router), 2e18);

        vm.expectRevert(Router.UnableToSendEther.selector);
        router.addLiquidityETH{ value: 1e18 }(address(token0), 1e17, 1e18, 1e17, erc20Contract, deadline);
    }

    function test_Revert_insufficientAAmount_removeLiquidity() public {
        uint256 token0transferAmount = 1e18;
        uint256 token1transferAmount = 1e18;
        (,, uint256 liquidity) = _addLiquidity(token0transferAmount, token1transferAmount);

        pair.approve(address(router), liquidity);

        vm.expectRevert(Router.InsufficientAAmount.selector);
        router.removeLiquidity(
            address(token0),
            address(token1),
            liquidity,
            token0transferAmount,
            token1transferAmount,
            address(this),
            deadline
        );
    }

    function test_Revert_insufficientBAmount_removeLiquidity() public {
        uint256 token0transferAmount = 1e18;
        uint256 token1transferAmount = 1e18;
        (,, uint256 liquidity) = _addLiquidity(token0transferAmount, token1transferAmount);

        pair.approve(address(router), liquidity);

        vm.expectRevert(Router.InsufficientBAmount.selector);
        router.removeLiquidity(
            address(token0),
            address(token1),
            liquidity,
            token0transferAmount - 10 ** 3,
            token1transferAmount,
            address(this),
            deadline
        );
    }

    function test_Revert_unableToSendEther_removeLiquidityETHSupportingFeeOnTransferTokens() public {
        address erc20Contract = makeAddr("erc20Contract");
        vm.etch(erc20Contract, "1");

        vm.deal(erc20Contract, 1e18);
        token0.transfer(erc20Contract, 5e18);
        weth.transfer(erc20Contract, 5e18);

        vm.startPrank(erc20Contract);

        uint256 token0ApprovedAmt = 1e18;
        uint256 wethApprovedAmt = 1e18;

        token0.approve(address(router), token0ApprovedAmt);
        weth.approve(address(router), wethApprovedAmt);

        (,, uint256 liquidity) = router.addLiquidityETH{ value: 1e18 }(
            address(token0), token0ApprovedAmt, 1e18, 1e18, erc20Contract, deadline
        );

        address pairAddress = pairFactory.getPair(address(token0), address(weth));

        Pair(pairAddress).approve(address(router), liquidity);

        vm.expectRevert(Router.UnableToSendEther.selector);
        router.removeLiquidityETHSupportingFeeOnTransferTokens(
            address(token0), liquidity, token0ApprovedAmt - 10 ** 3, wethApprovedAmt - 10 ** 3, erc20Contract, deadline
        );
    }

    function test_Revert_insufficientOutputAmount_swapExactTokensForTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.InsufficientOutputAmount.selector);
        router.swapExactTokensForTokens(3e17, 1e18, path, address(this), deadline);
    }

    function test_Revert_excessiveInputAmount_swapTokensForExactTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.ExcessiveInputAmount.selector);
        router.swapTokensForExactTokens(amount2Out, 1e16, path, address(this), deadline);
    }

    function test_Revert_invalidPath_swapExactETHForTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        weth.approve(address(router), 3e17);

        vm.expectRevert(Router.InvalidPath.selector);
        router.swapExactETHForTokens{ value: 3e17 }(1e18, path, address(this), deadline);
    }

    function test_Revert_insufficientOutputAmount_swapExactETHForTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(token1);
        path[2] = address(token0);

        weth.approve(address(router), 3e17);

        vm.expectRevert(Router.InsufficientOutputAmount.selector);
        router.swapExactETHForTokens{ value: 3e17 }(1e18, path, address(this), deadline);
    }

    //function test_Revert_unableToTransferWETH_swapExactETHForTokens() public { }

    function test_Revert_invalidPath_swapTokensForExactETH() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[1] = address(weth);
        path[0] = address(token0);
        path[2] = address(token1);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.InvalidPath.selector);
        router.swapTokensForExactETH(amount2Out, 3e17, path, address(this), deadline);
    }

    function test_Revert_excessiveInputAmount_swapTokensForExactETH() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.ExcessiveInputAmount.selector);
        router.swapTokensForExactETH(amount2Out, 3e16, path, address(this), deadline);
    }

    function test_Revert_unableToSendEther_swapTokensForExactETH() public {
        address erc20Contract = makeAddr("erc20Contract");
        vm.etch(erc20Contract, "1");

        vm.deal(erc20Contract, 1e18);
        token0.transfer(erc20Contract, 5e18);
        token1.transfer(erc20Contract, 5e18);
        weth.transfer(erc20Contract, 5e18);

        vm.startPrank(erc20Contract);

        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, erc20Contract, deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.UnableToSendEther.selector);
        router.swapTokensForExactETH(amount2Out, 3e17, path, erc20Contract, deadline);
    }

    function test_Revert_invalidPath_swapExactTokensForETH() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(token1);
        path[2] = address(token0);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.InvalidPath.selector);
        router.swapExactTokensForETH(3e17, 1e17, path, address(this), deadline);
    }

    function test_Revert_insufficientOutputAmount_swapExactTokensForETH() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.InsufficientOutputAmount.selector);
        router.swapExactTokensForETH(3e17, 1e18, path, address(this), deadline);
    }

    function test_Revert_unableToSendEther_swapExactTokensForETH() public {
        address erc20Contract = makeAddr("erc20Contract");
        vm.etch(erc20Contract, "1");

        vm.deal(erc20Contract, 1e18);
        token0.transfer(erc20Contract, 5e18);
        token1.transfer(erc20Contract, 5e18);
        weth.transfer(erc20Contract, 5e18);

        vm.startPrank(erc20Contract);

        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, erc20Contract, deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.UnableToSendEther.selector);
        router.swapExactTokensForETH(3e17, 1e17, path, erc20Contract, deadline);
    }

    function test_Revert_invalidPath_swapETHForExactTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        weth.approve(address(router), 3e17);

        vm.expectRevert(Router.InvalidPath.selector);
        router.swapETHForExactTokens{ value: 3e17 }(amount2Out, path, address(this), deadline);
    }

    function test_Revert_excessiveInputAmount_swapETHForExactTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(token1);
        path[2] = address(token0);

        uint256 amount1Out = RouterLib.getAmountOut(3e17, 1e18, 1e18);
        uint256 amount2Out = RouterLib.getAmountOut(amount1Out, 1e18, 1e18);

        weth.approve(address(router), 3e17);

        vm.expectRevert(Router.ExcessiveInputAmount.selector);
        router.swapETHForExactTokens{ value: 3e16 }(amount2Out, path, address(this), deadline);
    }

    //function test_Revert_unableToTransferWETH_swapETHForExactTokens() public { }

    //function test_Revert_unableToSendEther_swapETHForExactTokens() public { }

    function test_Revert_insufficientOutputAmount_swapExactTokensForTokensSupportingFeeOnTransferTokens() public {
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        address[] memory path = new address[](2);
        path[0] = address(token0);
        path[1] = address(token1);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.InsufficientOutputAmount.selector);
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(3e17, 1e18, path, address(this), deadline);
    }

    function test_Revert_invalidPath_swapExactETHForTokensSupportingFeeOnTransferTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        weth.approve(address(router), 3e17);

        vm.expectRevert(Router.InvalidPath.selector);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: 3e17 }(1e18, path, address(this), deadline);
    }

    //function test_Revert_unableToTransferWETH_swapExactETHForTokensSupportingFeeOnTransferTokens() public { }

    function test_Revert_insufficientOutputAmount_swapExactETHForTokensSupportingFeeOnTransferTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(token1);
        path[2] = address(token0);

        weth.approve(address(router), 3e17);

        vm.expectRevert(Router.InsufficientOutputAmount.selector);
        router.swapExactETHForTokensSupportingFeeOnTransferTokens{ value: 3e17 }(1e18, path, address(this), deadline);
    }

    //function test_Revert_unableToTransferWETH_swapExactTokensForETHSupportingFeeOnTransferTokens() public { }

    function test_Revert_invalidPath_swapExactTokensForETHSupportingFeeOnTransferTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(weth);
        path[1] = address(token1);
        path[2] = address(token0);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.InvalidPath.selector);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(3e17, 1e17, path, address(this), deadline);
    }

    function test_Revert_insufficientOutputAmount_swapExactTokensForETHSupportingFeeOnTransferTokens() public {
        uint256 wethTransferredAmt = 1e18;
        uint256 token0TransferAmount = 1e18;
        uint256 token1TransferAmount = 1e18;

        _addLiquidity(token0TransferAmount, token1TransferAmount);

        token1.approve(address(router), token1TransferAmount);
        weth.approve(address(router), wethTransferredAmt);

        router.addLiquidityETH{ value: 1e18 }(
            address(token1), token1TransferAmount, 1e18, 1e18, address(this), deadline
        );

        address[] memory path = new address[](3);
        path[0] = address(token0);
        path[1] = address(token1);
        path[2] = address(weth);

        token0.approve(address(router), 3e17);

        vm.expectRevert(Router.InsufficientOutputAmount.selector);
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(3e17, 1e18, path, address(this), deadline);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      HELPERS
    //////////////////////////////////////////////////////////////////////////*/

    function _addLiquidity(
        uint256 _token0Amount,
        uint256 _token1Amount
    )
        private
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {
        token0.approve(address(router), _token0Amount);
        token1.approve(address(router), _token1Amount);
        (amountA, amountB, liquidity) = router.addLiquidity(
            address(token0),
            address(token1),
            _token0Amount,
            _token1Amount,
            _token0Amount,
            _token1Amount,
            address(this),
            deadline
        );
    }

    function _getPermitHash(
        Pair _pair,
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _nonce,
        uint256 _deadline
    )
        private
        view
        returns (bytes32)
    {
        return keccak256(
            abi.encodePacked(
                "\x19\x01",
                _pair.DOMAIN_SEPARATOR(),
                keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, _nonce, _deadline))
            )
        );
    }
}
