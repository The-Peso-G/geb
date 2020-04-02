/// vox.t.sol -- tests for vox.sol

// Copyright (C) 2015-2020  DappHub, LLC
// Copyright (C) 2020       Stefan C. Ionescu <stefanionescu@protonmail.com>

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity ^0.5.15;

import "ds-test/test.sol";
import "ds-token/token.sol";

import {Vat} from '../vat.sol';
import {Jug} from "../jug.sol";
import {Vow} from '../vow.sol';
import {Vox1} from '../vox.sol';
import {GemJoin} from '../join.sol';
import {Spotter} from '../spot.sol';
import {Exp} from "../exp.sol";

contract Feed {
    bytes32 public val;
    bool public has;
    uint public zzz;
    constructor(uint256 initVal, bool initHas) public {
        val = bytes32(initVal);
        has = initHas;
        zzz = now;
    }
    function poke(uint256 val_) external {
        val = bytes32(val_);
        zzz = now;
    }
    function peek() external view returns (bytes32, bool) {
        return (val, has);
    }
}

contract Hevm {
    function warp(uint256) public;
}

contract Vox1Test is DSTest {
    Vat     vat;
    Spotter spot;
    Vox1    vox;
    Feed    stableFeed;

    GemJoin gemA;
    DSToken gold;
    Feed    goldFeed;

    Hevm    hevm;

    address vow;
    address self;

    uint256 pan  = 3;
    uint256 bowl = 6;
    uint256 mug  = 3;

    uint256 trim = 0.005 ether;

    uint constant SPY = 31536000;
    uint constant RAY = 10 ** 27;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, base)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = mul(x, y) / RAY;
    }

    function setUp() public {
        hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        hevm.warp(604411200);

        vow = address(0x123456789);

        vat = new Vat();
        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        gold = new DSToken("GEM");
        gold.mint(1000 ether);
        vat.init("gold");
        goldFeed = new Feed(1 ether, true);
        spot.file("gold", "pip", address(goldFeed));
        spot.file("gold", "tam", 1000000000000000000000000000);
        spot.file("gold", "mat", 1000000000000000000000000000);
        spot.poke("gold");
        gemA = new GemJoin(address(vat), "gold", address(gold));

        vat.file("gold", "line", rad(1000 ether));
        vat.file("Line",         rad(1000 ether));

        gold.approve(address(gemA));
        gold.approve(address(vat));

        vat.rely(address(gemA));

        gemA.join(address(this), 1000 ether);

        stableFeed = new Feed(1 ether, true);

        vox = new Vox1(address(spot), pan, bowl, mug);
        vox.file("pip", address(stableFeed));
        vox.file("trim", ray(trim));

        spot.rely(address(vox));

        self = address(this);

        vat.frob("gold", self, self, self, 10 ether, 5 ether);
    }

    function gem(bytes32 ilk, address urn) internal view returns (uint) {
        return vat.gem(ilk, urn);
    }
    function ink(bytes32 ilk, address urn) internal view returns (uint) {
        (uint ink_, uint art_) = vat.urns(ilk, urn); art_;
        return ink_;
    }
    function art(bytes32 ilk, address urn) internal view returns (uint) {
        (uint ink_, uint art_) = vat.urns(ilk, urn); ink_;
        return art_;
    }

    function add(uint x, int y) internal pure returns (uint z) {
        z = x + uint(y);
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function add(int x, int y) internal pure returns (int z) {
        z = x + y;
        require(y >= 0 || z <= x);
        require(y <= 0 || z >= x);
    }
    function mul(int x, uint y) internal pure returns (int z) {
        require(y == 0 || (z = x * int(y)) / int(y) == x);
    }
    function mul(int x, int y) internal pure returns (int z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // Market price simulations
    function monotonous_deviations(int side_, uint times) internal {
        uint price = 1 ether;
        for (uint i = 0; i <= bowl; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, trim * times));
          stableFeed.poke(price);
          vox.back();
        }
    }

    function major_one_side_deviations(int side_, uint times) internal {
        uint price = 1 ether; uint i;
        for (i = 0; i <= bowl / 2; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, trim * times));
          stableFeed.poke(price);
          vox.back();
        }
        for (i = bowl / 2; i <= bowl + 1; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_ * int(-1), trim));
          stableFeed.poke(price);
          vox.back();
        }
    }

    function zig_zag_deviations(int side_, uint times) internal {
        uint i;
        uint price;
        int aux = side_;
        for (i = 0; i <= bowl * 2; i++) {
          hevm.warp(now + 1 seconds);
          price = add(uint(1 ether), mul(aux, trim * times));
          stableFeed.poke(price);
          vox.back();
          aux = -aux;
        }
    }

    function subtle_deviations(int side_) internal {
        uint price = 1 ether;
        uint i;
        for (i = 0; i <= bowl + 5; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, trim / bowl));
          stableFeed.poke(price);
          vox.back();
        }
    }

    function sudden_big_deviation(int side_) internal {
        uint price = 1 ether;
        uint i;
        for (i = 0; i <= bowl; i++) {
          hevm.warp(now + 1 seconds);
          price = add(price, mul(side_, trim / bowl));
          stableFeed.poke(price);
          vox.back();
        }

        hevm.warp(now + 1 seconds);
        price = add(price, mul(side_ * int(-1), trim * 50));
        stableFeed.poke(price);
        vox.back();
    }

    function test_setup() public {
        assertTrue(address(vox.spot()) == address(spot));
    }

    function test_pid_increasing_deviations() public {
        monotonous_deviations(int(1), 1);

        assertEq(vox.path(), -1);
        assertEq(spot.way(), 999999987371733779393155516);
        assertEq(spot.rho(), now);
        assertEq(spot.par(), 999999987411027217746836585);
        assertEq(vox.fix(), ray(1.035 ether));
        assertEq(rmul(rpow(999999987371738246789463504, SPY, RAY), ray(1.035 ether)), 694999996504747453449106586);

        (int P, int I , int D, uint pid) = vox.full(vox.fix(), spot.par(), vox.path());

        assertEq(P, -35000012588972782253163415);
        assertEq(I, -135000012588972782253163415);
        assertEq(D, 2000000279754950716736964777);
        assertEq(pid, 1489208842898923378006058609);

        assertEq(mul(add(P, I), D) / int(RAY), -340000097914239794512858219);
        assertEq(add(vox.fix(), -340000097914239794512858219), 694999902085760205487141781);
        assertEq(spot.par() * RAY / 694999902085760205487141781, 1438848954875234358478140294);
    }

    // function test_pid_decreasing_deviations() public {
    //     monotonous_deviations(int(-1), 1);
    //
    //     assertEq(vox.path(), 1);
    //     assertEq(spot.way(), 1000000008441243084037259620);
    //     assertEq(spot.rho(), now);
    //     assertEq(spot.par(), 1000000008501931700174301437);
    //     assertEq(vox.fix(), ray(0.965 ether));
    //     assertEq(rmul(rpow(1000000008441243084037259620, SPY, RAY), ray(0.965 ether)), 0);
    //
    //     (int P, int I , int D, uint pid) = vox.full(spot.par(), vox.fix(), vox.path());
    //
    //     assertEq(P, 35000008501931700174301437);
    //     assertEq(I, 135000000000000000000000000);
    //     assertEq(D, 2000000000000000000000000000);
    //     assertEq(pid, 1305000005908842481384564294);
    //
    //     assertEq(mul(add(P, I), D) / int(RAY), 340000017003863400348602874);
    //     assertEq(add(vox.fix(), 340000017003863400348602874), 1305000017003863400348602874);
    //     assertEq(1305000017003863400348602874 * RAY / spot.par(), 1305000005908842481384564294);
    // }

    // function test_major_negative_deviations() public {
    //     major_one_side_deviations(-1, 2);
    //
    //     assertEq(vox.path(), 1);
    //
    //     assertEq(spot.way(), 1000000003104524158656075033);
    //     assertEq(spot.rho(), now);
    //     assertEq(spot.par(), 1000000019457540831238950507);
    //     assertEq(vox.fix(), ray(0.985 ether));
    //
    //     assertEq(vox.cron(1), int(-ray(0.01 ether)));
    //     assertEq(vox.cron(2), int(-ray(0.02 ether)));
    //     assertEq(vox.cron(3), int(-ray(0.03 ether)));
    //     assertEq(vox.cron(4), int(-ray(0.04 ether)));
    //     assertEq(vox.cron(5), int(-ray(0.035 ether)));
    //     assertEq(vox.cron(6), int(-ray(0.03 ether)));
    //
    //     assertEq(vox.fat(), int(-ray(0.105 ether)));
    //     assertEq(int(vox.thin()), int(-60000024533346077152986480));
    //     assertEq(vox.fit(), int(-165000024533346077152986480));
    //
    //     (int P, int I , int D, uint pid) = vox.full(spot.par(), vox.fix(), vox.path());
    //
    //     assertEq(P, 15000019457540831238950507);
    //     assertEq(I, 165000024533346077152986480);
    //     assertEq(D, 571428805079486449076061714);
    //     assertEq(pid, 1102857210051967501282919524);
    //     assertEq(int(ray(1 ether)) + P + I, 1180000043990886908391936987);
    // }

    // function test_major_positive_deviations() public {
    //     major_one_side_deviations(1, 3);
    //
    //     assertEq(vox.path(), -1);
    //
    //     assertEq(spot.way(), 999999993365388542556944540);
    //     assertEq(spot.rho(), now);
    //     assertEq(spot.par(), 999999968117093628044091396);
    //     assertEq(vox.fix(), ray(1.035 ether));
    //
    //     assertEq(vox.cron(1), int(ray(0.015 ether)));
    //     assertEq(vox.cron(2), int(ray(0.030 ether)));
    //     assertEq(vox.cron(3), int(ray(0.045 ether)));
    //     assertEq(vox.cron(4), int(ray(0.060 ether)));
    //     assertEq(vox.cron(5), int(ray(0.055 ether)));
    //     assertEq(vox.cron(6), int(ray(0.050 ether)));
    //
    //     assertEq(vox.fat(), int(ray(0.165 ether)));
    //     assertEq(int(vox.thin()), int(120000038073239137530902968));
    //     assertEq(vox.fit(), int(285000038073239137530902968));
    //
    //     (int P, int I , int D, uint pid) = vox.full(vox.fix(), spot.par(), vox.path());
    //
    //     assertEq(P, -35000031882906371955908604);
    //     assertEq(I, -285000038073239137530902968);
    //     assertEq(D, 727272958019631136550927078);
    //     assertEq(pid, 767272602556505159967494177);
    //     assertEq(int(ray(1 ether)) + P + I, 679999930043854490513188428);
    // }
    //
    // function test_zig_zag_deviations() public {
    //     zig_zag_deviations(-1, 20);
    //
    //     assertEq(vox.path(), 0);
    //
    //     assertEq(spot.way(), ray(1 ether));
    //     assertEq(spot.rho(), now);
    //     assertEq(spot.par(), ray(1 ether));
    //     assertEq(vox.fix(), ray(0.9 ether));
    //
    //     assertEq(vox.cron(1), int(-ray(0.1 ether)));
    //     assertEq(vox.cron(2), int(ray(0.1 ether)));
    //     assertEq(vox.cron(3), int(-ray(0.1 ether)));
    //     assertEq(vox.cron(4), int(ray(0.1 ether)));
    //     assertEq(vox.cron(5), int(-ray(0.1 ether)));
    //     assertEq(vox.cron(6), int(ray(0.1 ether)));
    //
    //     assertEq(vox.cron(7), int(-ray(0.1 ether)));
    //     assertEq(vox.cron(8), int(ray(0.1 ether)));
    //     assertEq(vox.cron(9), int(-ray(0.1 ether)));
    //     assertEq(vox.cron(10), int(ray(0.1 ether)));
    //     assertEq(vox.cron(11), int(-ray(0.1 ether)));
    //     assertEq(vox.cron(12), int(ray(0.1 ether)));
    //
    //     assertEq(vox.fat(), int(ray(0.1 ether)));
    //     assertEq(int(vox.thin()), int(-ray(0.1 ether)));
    //     assertEq(vox.fit(), 0);
    //
    //     (int P, int I , int D, uint pid) = vox.full(spot.par(), vox.fix(), vox.path());
    //
    //     assertEq(P, 0);
    //     assertEq(I, 0);
    //     assertEq(D, int(ray(1 ether)));
    //     assertEq(pid, ray(1 ether));
    // }

    // function test_sudden_big_negative_deviation() public {
    //     sudden_big_deviation(1);
    //
    // }
    //
    // function test_sudden_big_positive_deviation() public {
    //     sudden_big_deviation(-1);
    // }
    //
    // function test_deviation_waves() public {
    //     monotonous_deviations(-1, 5);
    //     // monotonous_deviations(1, 1);
    //
    //
    // }
    //
    // function test_drop_back_to_normal() public {
    //
    // }
}
