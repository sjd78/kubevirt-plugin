import { ReactNode } from 'react';

export type ColumnConfig<TData, TCallbacks = undefined> = {
  getValue?: (row: TData) => number | string;
  key: string;
  label: string;
  props?: Record<string, unknown>;
  renderCell: TCallbacks extends undefined
    ? (row: TData) => ReactNode
    : (row: TData, callbacks: TCallbacks) => ReactNode;
  sortable?: boolean;
};
