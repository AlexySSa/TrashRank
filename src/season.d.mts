import type {Member,RecordItem,Ranked} from './stats.mjs';
export const start:string,end:string,finish:string,zone:string;
export type Week={first:string;final:string;closed:boolean;rows:Ranked[];winners:Ranked[];total:number;participating:number};
export type Award={emoji:string;title:string;description:string;earned:boolean;progress?:number;target?:number};
export function seasonStats(members:Member[],records:RecordItem[],me:string,now?:Date):{overall:Ranked[];own:number;weeks:Week[];current:Week|undefined;past:Week|undefined;done:boolean;finalWinners:Ranked[];awards:Award[];total:number;activeCount:number};
