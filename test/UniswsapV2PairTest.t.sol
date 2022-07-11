// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./mocks/ERC20Mintable.sol";
import "/UniswapV2Pair.sol";

contract UniswapV2PairTest is Test {
    ERC20Mintable token0;
    ERC20Mintable token1;
    UniswapV2Pair pair;
    TestUser testUser;

    uint256 constant MINIMUM_LIQUIDITY = 1000;

    function setUp() public {
        testUser = new TestUser();

        token0 = new ERC20Mintable("Token A", "TKNA");
        token1 = new ERC20Mintable("Token B", "TKNB");
        pair = new UniswapV2Pair(address(token0), address(token1));

        token0.mint(10 ether, address(this));
        token1.mint(10 ether, address(this));

        token0.mint(10 ether, address(testUser));
        token1.mint(10 ether, address(testUser));
    }

    function assertReserves(uint112 expectedReserve0, uint112 expectedReserve1)
        internal
    {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        assertEq(reserve0, expectedReserve0, "unexpected reserve0");
        assertEq(reserve1, expectedReserve1, "unexpected reserve1");
    }

    function assertCumulativePrices(
        uint256 expectedPrice0,
        uint256 expectedPrice1
    ) internal {
        assertEq(
            pair.price0CumulativeLast(),
            expectedPrice0,
            "unexpected cumulative price 0"
        );
        assertEq(
            pair.price1CumulativeLast(),
            expectedPrice1,
            "unexpected cumulative price 1"
        );
    }

    function calculateCurrentPrice()
        internal
        returns (uint256 price0, uint256 price1)
    {
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        price0 = reserve0 > 0
            ? (reserve1 * uint256(UQ112x112.Q112)) / reserve0
            : 0;
        price1 = reserve1 > 0
            ? (reserve0 * uint256(UQ112x112.Q112)) / reserve1
            : 0;
    }

    function assertBlockTimestampLast(uint32 expected) internal {
        (, , uint32 blockTimestampLast) = pair.getReserves();

        assertEq(blockTimestampLast, expected, "unexpected blockTimestampLast");
    }

    function addLiquidity(uint256 amount0, uint256 amount1) internal {
        token0.transfer(address(pair), amount0);
        token1.transfer(address(pair), amount1);

        pair.mint();
    }

    function testMintBootstrap() public {
        uint112 amount = 1 ether;

        addLiquidity(amount, amount);

        assertEq(pair.balanceOf(address(this)), amount - MINIMUM_LIQUIDITY);
        assertReserves(amount, amount);
        assertEq(pair.totalSupply(), amount);
    }

    function testMintWhenTheresLiquidity() public {
        uint112 amount = 1 ether;
        uint112 amount2 = 2 ether;
        uint112 totalAmount = amount + amount2;

        addLiquidity(amount, amount);

        vm.warp(37);

        addLiquidity(amount2, amount2);

        assertEq(
            pair.balanceOf(address(this)),
            totalAmount - MINIMUM_LIQUIDITY
        );
        assertEq(pair.totalSupply(), totalAmount);
        assertReserves(totalAmount, totalAmount);
    }

    function testMintUnbalanced() public {
        addLiquidity(1 ether, 1 ether); // + 1 LP
        assertEq(pair.balanceOf(address(this)), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);

        addLiquidity(2 ether, 1 ether);

        assertEq(pair.balanceOf(address(this)), 2 ether - 1000);
        assertReserves(3 ether, 2 ether);
    }

    function testBurn() public {
        addLiquidity(1 ether, 1 ether);

        pair.burn();

        assertEq(pair.balanceOf(address(this)), 0);
        assertReserves(1000, 1000);
        assertEq(pair.totalSupply(), 1000);
        assertEq(token0.balanceOf(address(this)), 10 ether - 1000);
        assertEq(token1.balanceOf(address(this)), 10 ether - 1000);
    }

    function testBurnUnbalanced() public {
        addLiquidity(1 ether, 1 ether);

        uint256 totalAmount0 = 1 ether + 2 ether;
        uint256 totalAmount1 = 1 ether + 1 ether;

        addLiquidity(2 ether, 1 ether);

        pair.burn();

        assertEq(pair.balanceOf(address(this)), 0);
        assertReserves(1500, 1000);
        assertEq(pair.totalSupply(), 1000);
        assertEq(token0.balanceOf(address(this)), 10 ether - 1500);
        assertEq(token1.balanceOf(address(this)), 10 ether - 1000);
    }

    function testBurnUnbalancedDifferentUsers() public {
        testUser.provideLiquidity(
            address(pair),
            address(token0),
            address(token1),
            1 ether,
            1 ether
        );

        assertEq(pair.balanceOf(address(this)), 0);
        assertEq(pair.balanceOf(address(testUser)), 1 ether - 1000);
        assertEq(pair.totalSupply(), 1 ether);

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(); // + 1 LP

        pair.burn();

        assertEq(pair.balanceOf(address(this)), 0);
        assertReserves(1.5 ether, 1 ether);
        assertEq(pair.totalSupply(), 1 ether);
        assertEq(token0.balanceOf(address(this)), 10 ether - 0.5 ether);
        assertEq(token1.balanceOf(address(this)), 10 ether);

        testUser.withdrawLiquidity(address(pair));

        assertEq(pair.balanceOf(address(testUser)), 0);
        assertReserves(1500, 1000);
        assertEq(pair.totalSupply(), 1000);
        assertEq(
            token0.balanceOf(address(testUser)),
            10 ether + 0.5 ether - 1500
        );
        assertEq(token1.balanceOf(address(testUser)), 10 ether - 1000);
    }

    function testSwapBasicScenerio() public {
        addLiquidity(1 ether, 2 ether);

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0, 0.18 ether, address(this));

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether + 0.18 ether,
            "unexpected token1 balance"
        );
        assertReserves(1 ether + 0.1 ether, 2 ether - 0.18 ether);
    }

    function testSwapBasicScenerioReverseDirection() public {
        addLiquidity(1 ether, 2 ether);

        token1.transfer(address(pair), 0.2 ether);
        pair.swap(0.09 ether, 0, address(this));

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether + 0.09 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether - 0.2 ether,
            "unexpected token1 balance"
        );
        assertReserves(1 ether - 0.09 ether, 2 ether + 0.2 ether);
    }

    function testSwapBidirectional() public {
        addLiquidity(1 ether, 2 ether);

        token0.transfer(address(pair), 0.1 ether);
        token1.transfer(address(pair), 0.2 ether);
        pair.swap(0.09 ether, 0.18 ether, address(this));

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether + 0.09 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether - 0.2 ether + 0.18 ether,
            "unexpected token1 balance"
        );
        assertReserves(1 ether + 0.01 ether, 2 ether + 0.02 ether);
    }

    function testSwapZeroOut() public {
        addLiquidity(1 ether, 2 ether);

        vm.expectRevert(UniswapV2Pair.InsufficientOutputAmount.selector);
        pair.swap(0, 0, address(this));
    }

    function testSwapInsufficientLiquidity() public {
        addLiquidity(1 ether, 2 ether);

        vm.expectRevert(UniswapV2Pair.InsufficientLiquidity.selector);
        pair.swap(0, 2.1 ether, address(this));

        vm.expectRevert(UniswapV2Pair.InsufficientLiquidity.selector);
        pair.swap(1.1 ether, 0, address(this));
    }

    function testSwapUnderpriced() public {
        addLiquidity(1 ether, 2 ether);

        token0.transfer(address(pair), 0.1 ether);
        pair.swap(0, 0.09 ether, address(this));

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether + 0.09 ether,
            "unexpected token1 balance"
        );
        assertReserves(1 ether + 0.1 ether, 2 ether - 0.09 ether);
    }

    function testSwapOverpriced() public {
        addLiquidity(1 ether, 2 ether);

        token0.transfer(address(pair), 0.1 ether);

        vm.expectRevert(UniswapV2Pair.InvalidK.selector);
        pair.swap(0, 0.36 ether, address(this));

        assertEq(
            token0.balanceOf(address(this)),
            10 ether - 1 ether - 0.1 ether,
            "unexpected token0 balance"
        );
        assertEq(
            token1.balanceOf(address(this)),
            10 ether - 2 ether,
            "unexpected token1 balance"
        );
        assertReserves(1 ether, 2 ether);
    }

    function testCumulativePrices() public {
        vm.warp(0);
        addLiquidity(1 ether, 1 ether);

        (
            uint256 initialPrice0,
            uint256 initialPrice1
        ) = calculateCurrentPrice();

        // 0 seconds passed
        pair.sync();
        assertCumulativePrices(0, 0);

        // 1 seconds passed
        vm.warp(1);
        pair.sync();
        assertBlockTimestampLast(1);
        assertCumulativePrices(initialPrice0, initialPrice1);

        // 2 seconds passed
        vm.warp(2);
        pair.sync();
        assertBlockTimestampLast(2);
        assertCumulativePrices(initialPrice0 * 2, initialPrice1 * 2);

        // 3 seconds passed.
        vm.warp(3);
        pair.sync();
        assertBlockTimestampLast(3);
        assertCumulativePrices(initialPrice0 * 3, initialPrice1 * 3);

        // Change price
        addLiquidity(2, 1);

        (uint256 newPrice0, uint256 newPrice1) = calculateCurrentPrice();

        // 0 seconds since the last update
        assertCumulativePrices(initialPrice0 * 3, initialPrice1 * 3);

        // 1 second passed
        vm.warp(4);
        pair.sync();
        assertBlockTimestampLast(4);
        assertCumulativePrices(
            initialPrice0 * 3 + newPrice0,
            initialPrice1 * 3 + newPrice1
        );

        // 2 seconds passed;
        vm.warp(5);
        pair.sync();
        assertBlockTimestampLast(5);
        assertCumulativePrices(
            initialPrice0 * 3 + newPrice0 * 2,
            initialPrice1 * 3 + newPrice1 * 2
        );

        // 3 seconds passed.
        vm.warp(6);
        pair.sync();
        assertBlockTimestampLast(6);
        assertCumulativePrices(
            initialPrice0 * 3 + newPrice0 * 3,
            initialPrice1 * 3 + newPrice1 * 3
        );
    }
}

contract TestUser {
    function provideLiquidity(
        address pairAddress,
        address token0Address,
        address token1Address,
        uint256 amount0,
        uint256 amount1
    ) public {
        ERC20(token0Address).transfer(pairAddress, amount0);
        ERC20(token1Address).transfer(pairAddress, amount1);

        UniswapV2Pair(pairAddress).mint();
    }

    function withdrawLiquidity(address pairAddress_) public {
        UniswapV2Pair(pairAddress_).burn();
    }
}
