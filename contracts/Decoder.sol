//
// Copyright 2017 Christian Reitwiessner
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// 2019 OKIMS
//      ported to solidity 0.6
//      fixed linter warnings
//      added requiere error messages
//
//
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

contract Decoder {
    struct G1Point {
        uint X;
        uint Y;
    }
    struct G2Point {
        uint[2] X;
        uint[2] Y;
    }
    struct Proof {
        G1Point A;
        G2Point B;
        G1Point C;
    }

    // Scalar field size
    uint256 constant r    = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
    // Base field size
    uint256 constant q   = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // Verification Key data
    uint256 constant alphax  = 7506542393861712633345351046961518695186434969159573929710445813801252250723;
    uint256 constant alphay  = 16226065335411284296170178517395602646321797300570911178122732619405801531786;
    uint256 constant betax1  = 18085759018360810108311053436144684567975240874798592024271494525670832624248;
    uint256 constant betax2  = 14634453066859375398229234242235662432488733031061395747558146261931733463655;
    uint256 constant betay1  = 5381338245488965956306749233704530527583477992038243832593582681279872987470;
    uint256 constant betay2  = 15883666510464263642223723115318135885418478949233288914773546058946554436604;
    uint256 constant gammax1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 constant gammax2 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 constant gammay1 = 4082367875863433681332203403145435568316851327593401208105741076214120093531;
    uint256 constant gammay2 = 8495653923123431417604973247489272438418190587263600148770280649306958101930;
    uint256 constant deltax1 = 12835677679493139045269931295051448329793403398705026697877485711464362140790;
    uint256 constant deltax2 = 10890565504224301114874433160320698556606628868096993643809081156365267213249;
    uint256 constant deltay1 = 4820425325906337717692330783154620996810762479415825588979740850757518563223;
    uint256 constant deltay2 = 20093054666161765761327580477678108845241889769892444974271179780900242692838;


    uint256 constant IC0x = 15916933300299841326133363619464745675297622793331552584323366408211376395967;
    uint256 constant IC0y = 2204695882423366014128738034688798906136516188846113906761598291124965575312;

    uint256 constant IC1x = 4622856607165460859549457180034620471823207414430476098696107310517129298612;
    uint256 constant IC1y = 8316856443679694570367215915233834858969193163656242228258052534650350302793;

    uint256 constant IC2x = 5915523109966219878936187973377718245049119188043618969861196210655718832719;
    uint256 constant IC2y = 19707299613116331139635042453248814599694182156604393507335721697711099774908;

    uint256 constant IC3x = 11851222670115883100836444147396391086571308795728318034006095130793195411204;
    uint256 constant IC3y = 21124748331098730840633663986704312647589675061705229552977471659873651158043;


    // Memory data
    uint16 constant pVk = 0;
    uint16 constant pPairing = 128;

    uint16 constant pLastMem = 896;

    function verifyProof(uint[2] calldata _pA, uint[2][2] calldata _pB, uint[2] calldata _pC, uint[3] calldata _pubSignals) public view returns (bool) {
        assembly {
            function checkField(v) {
                if iszero(lt(v, q)) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

        // G1 function to multiply a G1 value(x,y) to value in an address
            function g1_mulAccC(pR, x, y, s) {
                let success
                let mIn := mload(0x40)
                mstore(mIn, x)
                mstore(add(mIn, 32), y)
                mstore(add(mIn, 64), s)

                success := staticcall(sub(gas(), 2000), 7, mIn, 96, mIn, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }

                mstore(add(mIn, 64), mload(pR))
                mstore(add(mIn, 96), mload(add(pR, 32)))

                success := staticcall(sub(gas(), 2000), 6, mIn, 128, pR, 64)

                if iszero(success) {
                    mstore(0, 0)
                    return(0, 0x20)
                }
            }

            function checkPairing(pA, pB, pC, pubSignals, pMem) -> isOk {
                let _pPairing := add(pMem, pPairing)
                let _pVk := add(pMem, pVk)

                mstore(_pVk, IC0x)
                mstore(add(_pVk, 32), IC0y)

            // Compute the linear combination vk_x

                g1_mulAccC(_pVk, IC1x, IC1y, calldataload(add(pubSignals, 0)))

                g1_mulAccC(_pVk, IC2x, IC2y, calldataload(add(pubSignals, 32)))

                g1_mulAccC(_pVk, IC3x, IC3y, calldataload(add(pubSignals, 64)))


            // -A
                mstore(_pPairing, calldataload(pA))
                mstore(add(_pPairing, 32), mod(sub(q, calldataload(add(pA, 32))), q))

            // B
                mstore(add(_pPairing, 64), calldataload(pB))
                mstore(add(_pPairing, 96), calldataload(add(pB, 32)))
                mstore(add(_pPairing, 128), calldataload(add(pB, 64)))
                mstore(add(_pPairing, 160), calldataload(add(pB, 96)))

            // alpha1
                mstore(add(_pPairing, 192), alphax)
                mstore(add(_pPairing, 224), alphay)

            // beta2
                mstore(add(_pPairing, 256), betax1)
                mstore(add(_pPairing, 288), betax2)
                mstore(add(_pPairing, 320), betay1)
                mstore(add(_pPairing, 352), betay2)

            // vk_x
                mstore(add(_pPairing, 384), mload(add(pMem, pVk)))
                mstore(add(_pPairing, 416), mload(add(pMem, add(pVk, 32))))


            // gamma2
                mstore(add(_pPairing, 448), gammax1)
                mstore(add(_pPairing, 480), gammax2)
                mstore(add(_pPairing, 512), gammay1)
                mstore(add(_pPairing, 544), gammay2)

            // C
                mstore(add(_pPairing, 576), calldataload(pC))
                mstore(add(_pPairing, 608), calldataload(add(pC, 32)))

            // delta2
                mstore(add(_pPairing, 640), deltax1)
                mstore(add(_pPairing, 672), deltax2)
                mstore(add(_pPairing, 704), deltay1)
                mstore(add(_pPairing, 736), deltay2)


                let success := staticcall(sub(gas(), 2000), 8, _pPairing, 768, _pPairing, 0x20)

                isOk := and(success, mload(_pPairing))
            }

            let pMem := mload(0x40)
            mstore(0x40, add(pMem, pLastMem))

        // Validate that all evaluations ∈ F

            checkField(calldataload(add(_pubSignals, 0)))

            checkField(calldataload(add(_pubSignals, 32)))

            checkField(calldataload(add(_pubSignals, 64)))

            checkField(calldataload(add(_pubSignals, 96)))


        // Validate all evaluations
            let isValid := checkPairing(_pA, _pB, _pC, _pubSignals, pMem)

            mstore(0, isValid)
            return(0, 0x20)
        }
    }

    function verifyDecoding(uint[3] memory input, Proof memory proof) public view returns (uint) {
        if (this.verifyProof([proof.A.X, proof.A.Y],[[proof.B.X[0], proof.B.X[1]], [proof.B.Y[0], proof.B.Y[1]]], [proof.C.X, proof.C.Y], input))
            return 0;
        return 1;
    }

    /// @return r  bool true if proof is valid
    // function verifyProof(
    //         uint[2] memory a,
    //         uint[2][2] memory b,
    //         uint[2] memory c,
    //         uint[3] memory input
    //     ) public view returns (bool r) {
    //     Proof memory proof;
    //     proof.A = Pairing.G1Point(a[0], a[1]);
    //     proof.B = Pairing.G2Point([b[0][0], b[0][1]], [b[1][0], b[1][1]]);
    //     proof.C = Pairing.G1Point(c[0], c[1]);
    //     uint[] memory inputValues = new uint[](input.length);
    //     for(uint i = 0; i < input.length; i++){
    //         inputValues[i] = input[i];
    //     }
    //     if (verify(inputValues, proof) == 0) {
    //         return true;
    //     } else {
    //         return false;
    //     }
    // }
}
