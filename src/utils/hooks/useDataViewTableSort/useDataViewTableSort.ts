import { useCallback, useMemo } from 'react';

import { universalComparator } from '@kubevirt-utils/utils/utils';
import { DataViewTh, useDataViewSort } from '@patternfly/react-data-view';
import { ThProps } from '@patternfly/react-table';

import { ColumnConfig } from './types';

export const useDataViewTableSort = <TData, TCallbacks = undefined>(
  data: TData[],
  columns: ColumnConfig<TData, TCallbacks>[],
  initialSortKey?: string,
): { sortedData: TData[]; tableColumns: DataViewTh[] } => {
  const { direction, onSort, sortBy } = useDataViewSort({
    initialSort: { direction: 'asc', sortBy: initialSortKey ?? columns[0]?.key },
  });

  const sortByIndex = useMemo(
    () => columns.findIndex((col) => col.key === sortBy),
    [sortBy, columns],
  );

  const getSortParams = useCallback(
    (columnIndex: number): ThProps['sort'] | undefined => {
      if (!columns[columnIndex]?.sortable) return undefined;
      return {
        columnIndex,
        onSort: (_event, index, dir) => onSort(_event, columns[index].key, dir),
        sortBy: { defaultDirection: 'asc', direction, index: sortByIndex },
      };
    },
    [columns, direction, onSort, sortByIndex],
  );

  const tableColumns: DataViewTh[] = useMemo(
    () =>
      columns.map((col, index) => ({
        cell: col.label,
        props: { ...col.props, sort: getSortParams(index) },
      })),
    [columns, getSortParams],
  );

  const sortedData = useMemo(() => {
    const column = columns.find((col) => col.key === sortBy);
    const getValue = column?.getValue;
    if (!getValue || !direction) return data;

    return [...data].sort((a, b) => {
      const aVal = getValue(a);
      const bVal = getValue(b);
      const cmp =
        typeof aVal === 'number' && typeof bVal === 'number'
          ? aVal - bVal
          : universalComparator(aVal, bVal);
      return direction === 'asc' ? cmp : -cmp;
    });
  }, [data, sortBy, direction, columns]);

  return { sortedData, tableColumns };
};
