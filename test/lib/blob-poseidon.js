const { spawn } = require('child_process');
const {printlog} = require('./print')

// const pythonScriptPath = './scripts/blob_poseidon.py';
const pythonScriptPath = 'test/lib/scripts/blob_poseidon.py';
const args = ['0x1234', "11"];

function handlePyData(maskList,sampleIdxInKv_ru_list,encodingKey_mod_list ) {
    return function(data){
        let datastr = data.toString();
        let dataStrList = datastr.split('\n');
        let encodingKey_mod = dataStrList[4]
        let sampleIdxInKv_ru = dataStrList[5]
        let mask = dataStrList[6]
        printlog("calculate mask succeed:",mask," encodingKey_mod:",encodingKey_mod," sampleIdxInKv_ru:",sampleIdxInKv_ru)
        encodingKey_mod_list.push(encodingKey_mod)
        sampleIdxInKv_ru_list.push(sampleIdxInKv_ru)
        maskList.push(mask);
    }
}

function callPythonToGenreateMask(encodingKey_hexstr, sampleIdxInKv,handleDataFunc){
    let input_args = [encodingKey_hexstr,sampleIdxInKv] 
    const pythonProcess = spawn('python3', [pythonScriptPath, ...input_args]);
    printlog("execing callPythonMask")
    pythonProcess.stdout.on('data',handleDataFunc)
    pythonProcess.stderr.on('data', (data) => {
        console.error(`Pythone Script Err：${data}`);
    });
    pythonProcess.on('close', (code) => {
        printlog(`Python Program End：${code}`);
    });
}
exports.callPythonToGenreateMask = callPythonToGenreateMask
exports.handlePyData = handlePyData

// ===================== local test ================================
// const sleep = time => {
//     return new Promise(resolve => setTimeout(resolve, time)
//     )
// }

// async function test () {
//     await sleep(2000)
//     console.log("abc");
// }
// let testMaskList = [];
// let testSampleIdxInKv_ru_list = []
// let testEncodingKey_mod_list = []
// callPythonToGenreateMask(args[0],args[1],handlePyData(testMaskList,testSampleIdxInKv_ru_list,testEncodingKey_mod_list))
// setTimeout(() => {
//     console.log(testMaskList)
//     console.log(testSampleIdxInKv_ru_list)
//     console.log(testEncodingKey_mod_list)
// },2000)

// test()
// console.log("bcd")