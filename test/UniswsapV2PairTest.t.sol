// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.10;

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

    function testMintBootstrap() public {
        uint112 amount = 1 ether;
        token0.transfer(address(pair), amount);
        token1.transfer(address(pair), amount);

        pair.mint();

        assertEq(pair.balanceOf(address(this)), amount - MINIMUM_LIQUIDITY);
        assertReserves(amount, amount);
        assertEq(pair.totalSupply(), amount);
    }

    function testMintWhenTheresLiquidity() public {
        uint112 amount = 1 ether;
        uint112 amount2 = 2 ether;
        uint112 totalAmount = amount + amount2;

        token0.transfer(address(pair), amount);
        token1.transfer(address(pair), amount);

        pair.mint();

        vm.warp(37);

        token0.transfer(address(pair), amount2);
        token1.transfer(address(pair), amount2);

        pair.mint();

        assertEq(
            pair.balanceOf(address(this)),
            totalAmount - MINIMUM_LIQUIDITY
        );
        assertEq(pair.totalSupply(), totalAmount);
        assertReserves(totalAmount, totalAmount);
    }

    function testMintUnbalanced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint(); // + 1 LP
        assertEq(pair.balanceOf(address(this)), 1 ether - 1000);
        assertReserves(1 ether, 1 ether);

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint();
        assertEq(pair.balanceOf(address(this)), 2 ether - 1000);
        assertReserves(3 ether, 2 ether);
    }

    function testBurn() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint();

        pair.burn();

        assertEq(pair.balanceOf(address(this)), 0);
        assertReserves(1000, 1000);
        assertEq(pair.totalSupply(), 1000);
        assertEq(token0.balanceOf(address(this)), 10 ether - 1000);
        assertEq(token1.balanceOf(address(this)), 10 ether - 1000);
    }

    function testBurnUnbalanced() public {
        token0.transfer(address(pair), 1 ether);
        token1.transfer(address(pair), 1 ether);

        pair.mint();

        console.log(pair.balanceOf(address(this)));

        token0.transfer(address(pair), 2 ether);
        token1.transfer(address(pair), 1 ether);

        uint256 totalAmount0 = 1 ether + 2 ether;
        uint256 totalAmount1 = 1 ether + 1 ether;

        pair.mint(); // + 1 LP

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
