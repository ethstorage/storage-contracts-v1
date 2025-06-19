const { spawn } = require("child_process");
const { printlog } = require("./print");

const pythonScriptPath = "test/lib/scripts/blob_poseidon.py";

function handlePyData(maskList, sampleIdxInKv_ru_list, encodingKey_mod_list) {
  return function (data) {
    let datastr = data.toString();
    let dataStrList = datastr.split("\n");
    let encodingKey_mod = dataStrList[4];
    let sampleIdxInKv_ru = dataStrList[5];
    let mask = dataStrList[6];
    printlog(
      "calculate mask succeed:",
      mask,
      " encodingKey_mod:",
      encodingKey_mod,
      " sampleIdxInKv_ru:",
      sampleIdxInKv_ru,
    );
    encodingKey_mod_list.push(encodingKey_mod);
    sampleIdxInKv_ru_list.push(sampleIdxInKv_ru);
    maskList.push(mask);
  };
}

function callPythonToGenreateMask(encodingKey_hexstr, sampleIdxInKv, handleDataFunc) {
  let input_args = [encodingKey_hexstr, sampleIdxInKv];
  const pythonProcess = spawn("python3", [pythonScriptPath, ...input_args]);
  printlog("execing callPythonMask");

  return new Promise((resolve, reject) => {
    pythonProcess.stdout.on("data", function (data) {
      handleDataFunc(data);
      resolve();
    });

    pythonProcess.stderr.on("data", (data) => {
      console.error(`Pythone Script Err：${data}`);
      reject();
    });

    pythonProcess.on("close", (code) => {
      printlog(`Python Program End：${code}`);
      resolve();
    });
  });
}
exports.callPythonToGenreateMask = callPythonToGenreateMask;
exports.handlePyData = handlePyData;
