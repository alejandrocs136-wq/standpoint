const fs=require('fs');const js=fs.readFileSync(process.argv[2],'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
const cut=(a,b)=>js.slice(js.indexOf(a), js.indexOf(b));
const src=cut('var LIFTS = {','var BLOCK_NAMES')+js.slice(js.indexOf('var BLOCK_NAMES'), js.indexOf('};', js.indexOf('var BLOCK_NAMES'))+2)+cut('var EXINFO = [','function exInfo(')+cut('var AUTO_GOAL = {','function buildAuto');
const D=new Function(src+';return {LIFTS,MAIN_RX,PROGRAMS,SPEED,SPEED_LAB,BLOCK_NAMES,EXINFO,AUTO_GOAL,AUTO_EQ,AUTO_HIT,AUTO_ARMCARE};')();
const nov6Start=js.indexOf("// From Alejandro's Nov 6 sheets"), goalStart=js.indexOf('// Goal work in the automatic plans'), exStart=js.indexOf('var EXINFO = [');
const exBlock=js.slice(exStart, js.indexOf('function exInfo('));
D.EXINFO.forEach(e=>{const pos=js.indexOf(JSON.stringify(e[0]),exStart); e.push(pos<goalStart?'Alejandro\'s Nov 6 sheets':pos<js.indexOf('];',goalStart)&&pos>goalStart&&!/^\s*\["/.test('')? 'StandPoint goal work':'StandPoint base');});
// fix source: entries between nov6 and goal comment = Nov 6; between goal comment and first base entry = goal work
const firstBase=js.indexOf('["depth drop to box jump"',exStart);
D.EXINFO.forEach(e=>{const pos=js.indexOf('["'+e[0]+'"',exStart); e[6]= pos<goalStart?"Alejandro's Nov 6 sheets": pos<firstBase?'StandPoint goal work':'StandPoint base';});
fs.writeFileSync(process.argv[3], JSON.stringify(D,null,1));
console.log('exinfo',D.EXINFO.length,'nov6',D.EXINFO.filter(e=>e[6].startsWith('Alej')).length,'goal',D.EXINFO.filter(e=>e[6]==='StandPoint goal work').length);
