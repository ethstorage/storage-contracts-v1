const DEBUG_TAG = false 
function printlog(message , ...optionalParams){
  if (DEBUG_TAG) {
    console.log(message, ...optionalParams)
  }
}
exports.printlog = printlog