// Preset educational emphasis, never force, EMG or a muscle activation score.
export const REGIONS = {
  quads: {name:'股四头肌', color:[1,.12,.018], description:'大腿前侧：参与控制屈膝，起身时参与伸膝。'},
  glutes: {name:'臀大肌', color:[1,.21,.018], description:'臀部：参与髋部运动控制，起身时参与伸髋。短裤上的色块表示对应表面区域。'},
  core: {name:'躯干稳定区域', color:[.012,.5,.3], description:'腹部与腰背的示意区域：帮助躯干维持姿态，包含多组肌肉。'},
};

export function muscleDisplay(time, enabled, selected='all') {
  const phase=time<.5?'准备':time<3?'控制下蹲':time<3.5?'底部停顿':time<5.5?'起身':'回到起始';
  const descriptions={
    '准备':'建立站姿与躯干稳定，高亮帮助你定位本次展示的肌群。',
    '控制下蹲':'大腿前侧与臀部肌群参与控制下降，躯干肌群帮助维持姿态。',
    '底部停顿':'暂停移动时仍需保持支撑与姿态，相关区域持续显示。',
    '起身':'通过伸髋、伸膝起身，躯干继续保持稳定。',
    '回到起始':'回到站立位置，为下一次动作做准备。',
  };
  // Smooth emphasis around the active part of the clip; all three groups share
  // it so brightness never ranks one muscle's force against another's.
  const fade=t=>{const x=Math.max(0,Math.min(1,t));return x*x*(3-2*x);};
  const emphasis=.58+.22*fade((time-.5)/.55)*fade((5.5-time)/.55);
  const opacity=Object.fromEntries(Object.keys(REGIONS).map(k=>[k,
    !enabled?0:(selected==='all'||selected===k?emphasis:.045)]));
  return {phase, opacity, text:descriptions[phase],
    detail:selected==='all'?'本样板展示部分相关肌群；颜色区分参与角色，明暗仅提示动作阶段。':REGIONS[selected].description};
}
