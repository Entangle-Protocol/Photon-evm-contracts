import * as fs from "fs";
import { task, types } from "hardhat/config";
import { HardhatRuntimeEnvironment } from "hardhat/types";
import path from "path";

const mapValues = <T extends object, U>(o: T, mapFn: (arg: T[keyof T]) => U) =>
    Object.fromEntries(
        Object.entries(o).map(([k, v]) => {
            const o = mapFn(v);
            if (o === undefined) {
                return [];
            }
            return [k, o];
        })
    );

task("func-sig-json", "Get function signatures for Contracts")
    .addOptionalParam("out", "Output file path", undefined, types.string)
    .setAction(async (taskArgs: { out?: string }, hre) => {
        const out = getFuncSignatures(hre);
        const tmp = mapValues(out, el =>
            mapValues(el, e => (e.Type == "function" ? e.Sighash : undefined))
        );
        // Hack to remove undefined values
        const res = JSON.parse(JSON.stringify(tmp));

        if (!taskArgs.out) {
            console.log(res);
        }

        if (taskArgs.out) {
            fs.writeFileSync(taskArgs.out, JSON.stringify(res, null, 4));
            console.log(`Saved as ${taskArgs.out}`);
        }
    });

task("old-func-sig-json", "Get function signatures for Contracts")
    .addOptionalParam("out", "Output file path", undefined, types.string)
    .setAction(async (taskArgs: { out?: string }, hre) => {
        const out = getFuncSignatures(hre);
        const tmp = mapValues(out, el =>
            mapValues(el, e => (e.Type == "function" ? e.Sighash : undefined))
        );
        // Hack to remove undefined values
        const clean = JSON.parse(JSON.stringify(tmp)) as Record<string, Record<string, string>>;
        // Just flatten the object
        const res = Object.values(clean).reduce((acc, el) => ({ ...acc, ...el }), {});

        if (!taskArgs.out) {
            console.log(res);
        }

        if (taskArgs.out) {
            fs.writeFileSync(taskArgs.out, JSON.stringify(res, null, 4));
            console.log(`Saved as ${taskArgs.out}`);
        }
    });

// iba - abi backwards
task("combined-iba", "Get function signatures for Contracts")
    .addOptionalParam("out", "Output file path", undefined, types.string)
    .setAction(async (taskArgs: { out?: string }, hre) => {
        const res = getFuncSignatures(hre);

        if (!taskArgs.out) {
            console.log(res);
        }

        if (taskArgs.out) {
            fs.writeFileSync(taskArgs.out, JSON.stringify(res, null, 4));
            console.log(`Saved as ${taskArgs.out}`);
        }
    });

interface Info {
    Type: "function" | "event" | "error";
    Name: string;
    Params: string[];
    Sighash: string;
}

type E = {
    [contractName: string]: {
        [signature: string]: Info;
    };
};

export function getFuncSignatures(hre: HardhatRuntimeEnvironment) {
    const out: E = {};
    const contractLocation = hre.config.paths.sources;
    const files = getFiles(path.join(hre.config.paths.artifacts, path.basename(contractLocation)));
    const source = path.basename(hre.config.paths.sources);
    for (const file of files) {
        const abiPath = path.join(hre.config.paths.artifacts, source, file);
        const iface = new hre.ethers.Interface(JSON.parse(fs.readFileSync(abiPath, "utf8")).abi);
        const name = path.basename(file).replace(".json", "");
        const infos: Record<string, Info> = {};

        iface.forEachFunction(func => {
            infos[func.selector] = {
                Type: "function",
                Name: func.name,
                Params: func.inputs.map(e => e.type),
                Sighash: func.format("sighash"),
            };
        });

        iface.forEachEvent(event => {
            infos[event.topicHash] = {
                Type: "event",
                Name: event.name,
                Params: event.inputs.map(e => e.type),
                Sighash: event.format("sighash"),
            };
        });

        iface.forEachError(error => {
            infos[error.selector] = {
                Type: "error",
                Name: error.name,
                Params: error.inputs.map(e => e.type),
                Sighash: error.format("sighash"),
            };
        });
        out[name] = infos;
    }

    return out;
}

const getFiles = (filePath: fs.PathLike) => {
    const files = [];
    for (const file of fs.readdirSync(filePath)) {
        const fullPath = filePath + "/" + file;
        if (fs.lstatSync(fullPath).isDirectory()) {
            getFiles(fullPath).forEach(x => files.push(file + "/" + x));
        } else {
            files.push(file);
        }
    }
    return files.filter(file => {
        return !path.basename(file).toLowerCase().endsWith(".dbg.json");
    });
};
