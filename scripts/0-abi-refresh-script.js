const fs = require("fs");

async function main() {
    let directory_name = "./artifacts/contracts"; 
    let filenames = fs.readdirSync(directory_name);

    console.log("Starting ABI files update..."); 

    // Delete the existing contract files
    let dir = "./src/abis/";
    fs.rmSync(dir, { recursive: true, force: true });
    fs.mkdirSync(dir, { recursive: true, force: true });

    filenames.forEach((file) => { 
        let contractName = fs.readdirSync(directory_name + "/" + file); 

        contractName.forEach((contract) => { 
            if(!contract.includes(".dbg.json")) {            
                fs.readFile(directory_name + "/" + file + "/" + contract, 'utf8', function(err, data) {
                    if (err) {
                        return console.log(err);
                    }
                    try {
                        // Parse the JSON data
                        const jsonData = JSON.parse(data);
                    
                        // Now you have the JSON data in memory and format it
                        let abi = JSON.stringify(jsonData.abi, null, 2);                    

                        fs.writeFile(dir + contract, abi, (err) => {
                            if (err) {
                            console.error(err);
                            return;
                            }
                            console.log(`ABI file (${contract}) created successfully!`);
                        });
                    } catch (parseError) {
                        console.error('Error parsing JSON:', parseError);
                    }
                });
            }      
        }); 
    }); 
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
  });