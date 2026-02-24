import { ReactNode } from 'react';

import { DataViewTr } from '@patternfly/react-data-view';

import { ColumnConfig } from './types';

export const generateRows = <TData, TCallbacks = undefined>(
  data: TData[],
  columns: ColumnConfig<TData, TCallbacks>[],
  callbacks: TCallbacks,
  getRowId?: (row: TData, index: number) => string,
): DataViewTr[] =>
  data.map((row, index) => ({
    id: getRowId?.(row, index) ?? String(index),
    row: columns.map((col) => ({
      cell:
        callbacks != null
          ? (col.renderCell as (row: TData, cb: TCallbacks) => ReactNode)(row, callbacks)
          : (col.renderCell as (row: TData) => ReactNode)(row),
      props: col.props,
    })),
  }));
